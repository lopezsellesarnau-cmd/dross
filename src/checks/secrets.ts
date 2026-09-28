import { execFileSync } from 'node:child_process'
import { lstatSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { basename, join } from 'node:path'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { loadDrossIgnore, type IgnoreRules } from '../ignore.js'

/**
 * Hardcoded secrets — the most expensive thing that can reach production:
 * a live key in source is leaked the moment the repo (or a bundle) is shared.
 *
 * The line Dross draws: a key in an env var / gitignored .env is fine; a key
 * anywhere it will leave the machine is not. Deterministic passes, known
 * formats only (no entropy guessing — that is where secret scanners drown
 * users in false positives):
 *   1. Provider key formats (Anthropic, OpenAI, Stripe live, AWS, GitHub,
 *      Slack, SendGrid, private key blocks) in every text file git would
 *      ship — any language, config, docs — not just JS/TS.
 *   2. Secret-bearing files (.env with values, private keys, Apple .p8,
 *      service-account JSON) that are tracked by git, or untracked but not
 *      gitignored (the next `git add .` commits them).
 *   3. Secrets in client-public env vars (EXPO_PUBLIC_ / NEXT_PUBLIC_ /
 *      VITE_ / REACT_APP_): they live in .env but get baked into the bundle.
 *
 * Comments are NOT stripped: a key in a comment leaks just the same.
 * Messages never echo the full value — reports end up in CI logs.
 * Pattern literals are assembled from parts so this file does not flag itself.
 * Google `AIza…` keys are deliberately skipped: Firebase web keys are public
 * by design and would be constant noise.
 */

type KeyPattern = { re: RegExp; label: string }

const KEY_PATTERNS: KeyPattern[] = [
  { re: new RegExp(`\\b${'sk-' + 'ant-'}(?:api|admin)\\d{2}-[A-Za-z0-9_-]{20,}`, 'g'), label: 'Anthropic API key' },
  { re: new RegExp(`\\b${'sk-' + 'proj-'}[A-Za-z0-9_-]{20,}`, 'g'), label: 'OpenAI API key' },
  { re: new RegExp(`\\bsk-[A-Za-z0-9]{20}${'T3Blbk' + 'FJ'}[A-Za-z0-9]{20}\\b`, 'g'), label: 'OpenAI API key' },
  { re: new RegExp(`\\b(?:sk|rk)_${'li' + 've'}_[A-Za-z0-9]{20,}`, 'g'), label: 'Stripe live secret key' },
  { re: new RegExp(`\\b(?:${'AK' + 'IA'}|${'AS' + 'IA'})[A-Z0-9]{16}\\b`, 'g'), label: 'AWS access key ID' },
  { re: new RegExp(`\\b${'gh'}[pousr]_[A-Za-z0-9]{36,}\\b`, 'g'), label: 'GitHub token' },
  { re: new RegExp(`\\b${'github' + '_pat_'}[A-Za-z0-9_]{22,}`, 'g'), label: 'GitHub token' },
  { re: new RegExp(`\\b${'xo' + 'x'}[baprs]-[A-Za-z0-9-]{10,}`, 'g'), label: 'Slack token' },
  { re: new RegExp(`\\b${'S' + 'G'}\\.[A-Za-z0-9_-]{22}\\.[A-Za-z0-9_-]{43}\\b`, 'g'), label: 'SendGrid API key' },
  {
    re: new RegExp(`-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?${'PRIVATE' + ' KEY'}( BLOCK)?-----`, 'g'),
    label: 'private key',
  },
]

/** Docs/sample values — `AKIAIOSFODNN7EXAMPLE`, `sk_live_xxxxxxxx…`, `your_key_here`. */
const PLACEHOLDER = /example|xxxx|placeholder|dummy|redacted|your[_-]|\*\*\*/i

function lineNumberAt(text: string, index: number): number {
  let line = 1
  for (let i = 0; i < index && i < text.length; i++) {
    if (text.charCodeAt(i) === 10) line++
  }
  return line
}

/** First few chars only — enough to find it, not enough to reuse it. */
function redact(value: string): string {
  return value.startsWith('-----') ? value : `${value.slice(0, 8)}…`
}

function scanTextForKeys(text: string, file: string): Finding[] {
  const findings: Finding[] = []
  for (const { re, label } of KEY_PATTERNS) {
    re.lastIndex = 0
    let m: RegExpExecArray | null
    while ((m = re.exec(text))) {
      if (PLACEHOLDER.test(m[0])) continue
      findings.push({
        check: 'hardcoded-secrets',
        severity: 'finding',
        file,
        line: lineNumberAt(text, m.index),
        message: `${label} hardcoded in source ("${redact(m[0])}") — anyone with the repo or the bundle can use it. Move it to an env var and rotate the key.`,
        fixHint: 'open-editor',
      })
    }
  }
  return findings
}

/** Key formats in already-collected JS/TS sources — the non-git fallback. */
export function checkSecrets(files: SourceFile[]): Finding[] {
  return files.flatMap((f) => scanTextForKeys(f.text, f.relPath))
}

/** `.env`, `.env.local`, `.env.production`… but not the templates. */
const ENV_FILE = /^\.env(?:\.[\w.-]+)?$/
const ENV_TEMPLATE = /\.(?:example|sample|template|dist|defaults)$/
/** Env files teams often commit on purpose with non-secret values. */
const ENV_LOW_RISK = /^\.env\.(?:development|test)$/

type TrackedRule = { test: (name: string) => boolean; label: string; needs?: RegExp }

const TRACKED_RULES: TrackedRule[] = [
  { test: (n) => /^id_(?:rsa|dsa|ecdsa|ed25519)$/.test(n), label: 'SSH private key' },
  { test: (n) => /\.(?:pem|key)$/i.test(n), label: 'private key file', needs: /PRIVATE KEY-----/ },
  { test: (n) => /\.p8$/i.test(n), label: 'Apple private key (.p8)' },
  { test: (n) => /\.(?:p12|pfx|jks|keystore)$/i.test(n), label: 'certificate / keystore bundle' },
  {
    test: (n) => /\.json$/i.test(n) && /(?:service[-_]?account|firebase-adminsdk|credentials)/i.test(n),
    label: 'service-account credentials',
    needs: /"private_key"\s*:/,
  },
]

/** Files git would ship: tracked, plus untracked-but-not-ignored. Null = not a git repo. */
function gitFiles(root: string): { tracked: string[]; untracked: string[] } | null {
  const run = (args: string[]) =>
    execFileSync('git', ['-C', root, 'ls-files', '-z', ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 10_000,
      maxBuffer: 64 * 1024 * 1024,
    })
      .split('\0')
      .filter(Boolean)
  try {
    return { tracked: run([]), untracked: run(['--others', '--exclude-standard']) }
  } catch {
    return null // not a git repo, or git missing
  }
}

function readSafe(abs: string): string {
  try {
    return readFileSync(abs, 'utf8')
  } catch {
    return ''
  }
}

/** True when an env file assigns at least one non-empty value. */
function envHasValues(text: string): boolean {
  return text.split('\n').some((raw) => {
    const line = raw.trim()
    if (!line || line.startsWith('#')) return false
    const m = line.match(/^(?:export\s+)?[A-Za-z_][\w]*\s*=\s*(.*)$/)
    const value = m?.[1]?.replace(/^['"]|['"]$/g, '').trim()
    return !!value
  })
}

/** A secret-bearing file by name (+ content where the name alone is ambiguous). */
function secretFileKind(root: string, rel: string): { label: string; lowRisk: boolean } | null {
  const name = basename(rel)
  if (ENV_FILE.test(name) && !ENV_TEMPLATE.test(name)) {
    if (!envHasValues(readSafe(join(root, rel)))) return null
    return { label: name, lowRisk: ENV_LOW_RISK.test(name) }
  }
  for (const rule of TRACKED_RULES) {
    if (!rule.test(name)) continue
    if (rule.needs && !rule.needs.test(readSafe(join(root, rel)))) continue
    return { label: rule.label, lowRisk: false }
  }
  return null
}

function secretFileFinding(file: string, kind: { label: string; lowRisk: boolean }, tracked: boolean): Finding {
  if (!tracked) {
    return {
      check: 'hardcoded-secrets',
      severity: 'finding',
      file,
      message: `${kind.label} is not in .gitignore — the next \`git add .\` commits it. Add it to .gitignore now.`,
      fixHint: 'open-editor',
    }
  }
  if (kind.lowRisk) {
    return {
      check: 'hardcoded-secrets',
      severity: 'warning',
      file,
      message: `${kind.label} with values is tracked by git — fine only if nothing in it is secret.`,
      fixHint: 'open-editor',
    }
  }
  return {
    check: 'hardcoded-secrets',
    severity: 'finding',
    file,
    message: `${kind.label} is tracked by git — every secret in it is in your history, even if deleted later. Untrack it (git rm --cached), add it to .gitignore, and rotate what was in it.`,
    fixHint: 'open-editor',
  }
}

/** Binary / generated files where a key-format match is never meaningful. */
const SKIP_CONTENT =
  /\.(?:png|jpe?g|gif|webp|ico|icns|svg|pdf|zip|gz|tgz|dmg|mp[34]|mov|wav|ttf|otf|woff2?|pkl|ff1pkl|sqlite|db|parquet|jar|class|so|dylib|a|o)$|(?:^|\/)(?:package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|Podfile\.lock|pubspec\.lock)$/i
const MAX_TEXT_BYTES = 1_000_000

function readText(abs: string): string | null {
  try {
    if (statSync(abs).size > MAX_TEXT_BYTES) return null
    const text = readFileSync(abs, 'utf8')
    return text.includes('\0') ? null : text
  } catch {
    return null
  }
}

/** Client-bundled env prefixes — Expo, Next, Vite, CRA, SvelteKit/Astro. */
const PUBLIC_ENV = /^(?:EXPO_PUBLIC_|NEXT_PUBLIC_|VITE_|REACT_APP_|PUBLIC_)/
const SECRET_NAME = /SECRET|PRIVATE_KEY|SERVICE_ROLE/
const ENV_WALK_SKIP = new Set(['node_modules', '.git', 'dist', 'build', '.next', '.expo', 'Pods', '.build', 'coverage'])

/** Every .env* under root (depth-limited), gitignored ones included — they feed the bundle too. */
function findEnvFiles(root: string, depth = 4, rel = ''): string[] {
  let entries: string[]
  try {
    entries = readdirSync(join(root, rel))
  } catch {
    return []
  }
  const out: string[] = []
  for (const entry of entries) {
    if (ENV_WALK_SKIP.has(entry)) continue
    const childRel = rel ? join(rel, entry) : entry
    let st
    try {
      st = lstatSync(join(root, childRel))
    } catch {
      continue
    }
    if (st.isDirectory() && depth > 0) out.push(...findEnvFiles(root, depth - 1, childRel))
    else if (st.isFile() && ENV_FILE.test(entry)) out.push(childRel)
  }
  return out
}

function publicEnvFinding(file: string, line: number, name: string, why: string): Finding {
  return {
    check: 'hardcoded-secrets',
    severity: 'finding',
    file,
    line,
    message: `${name} ${why} — ${name.match(PUBLIC_ENV)?.[0]}* vars are baked into the app/web bundle, so every user can read it. Keep the secret server-side and call it through your API.`,
    fixHint: 'open-editor',
  }
}

function checkPublicEnv(root: string, prefix: string, files: SourceFile[], rules: IgnoreRules): Finding[] {
  const findings: Finding[] = []
  for (const rel of findEnvFiles(root)) {
    if (rules.ignores(rel)) continue
    const lines = readSafe(join(root, rel)).split('\n')
    lines.forEach((raw, i) => {
      const m = raw.trim().match(/^(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*)$/)
      if (!m || !PUBLIC_ENV.test(m[1])) return
      const [, name, value] = m
      const file = prefix ? join(prefix, rel) : rel
      if (SECRET_NAME.test(name)) {
        findings.push(publicEnvFinding(file, i + 1, name, 'is named like a secret but is public'))
      } else if (scanTextForKeys(value, file).length) {
        findings.push(publicEnvFinding(file, i + 1, name, 'holds a secret API key'))
      }
    })
  }
  // Code reading a secret-named public var — catches it even when the value
  // only lives in the host's env UI (EAS / Vercel), never in a local file.
  const read = /(?:process\.env|import\.meta\.env)\.((?:EXPO_PUBLIC_|NEXT_PUBLIC_|VITE_|REACT_APP_|PUBLIC_)[A-Z0-9_]*)/g
  for (const f of files) {
    if (/\.(test|spec)\.[jt]sx?$/.test(f.relPath)) continue // tests never ship in a bundle
    read.lastIndex = 0
    let m: RegExpExecArray | null
    while ((m = read.exec(f.text))) {
      if (!SECRET_NAME.test(m[1])) continue
      findings.push(publicEnvFinding(f.relPath, lineNumberAt(f.text, m.index), m[1], 'is named like a secret but is public'))
    }
  }
  return findings
}

/**
 * All secrets findings for one scan root. `prefix` is the label the scan uses
 * for companion roots so paths line up with the rest of the report; `files`
 * are the JS/TS sources the scan already collected for this root.
 */
export function checkRepoSecrets(root: string, prefix = '', files: SourceFile[] = []): Finding[] {
  // Same .drossignore as the source walk (`files` is already filtered by it).
  const rules = loadDrossIgnore(root)
  const findings = checkPublicEnv(root, prefix, files, rules)
  const git = gitFiles(root)
  if (!git) return [...findings, ...checkSecrets(files)]

  const tracked = new Set(git.tracked)
  for (const rel of [...git.tracked, ...git.untracked]) {
    if (rules.ignores(rel)) continue
    const file = prefix ? join(prefix, rel) : rel
    const kind = secretFileKind(root, rel)
    if (kind) {
      // The file itself is the finding; its keys would just repeat it.
      findings.push(secretFileFinding(file, kind, tracked.has(rel)))
      continue
    }
    if (SKIP_CONTENT.test(rel)) continue
    const text = readText(join(root, rel))
    if (text) findings.push(...scanTextForKeys(text, file))
  }
  return findings
}
