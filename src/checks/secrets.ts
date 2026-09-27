import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { basename, join } from 'node:path'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'

/**
 * Hardcoded secrets — the most expensive thing that can reach production:
 * a live key in source is leaked the moment the repo (or a bundle) is shared.
 *
 * Two deterministic passes, known formats only (no entropy guessing — that
 * is where secret scanners drown users in false positives):
 *   1. Provider key formats inside source files (Anthropic, OpenAI, Stripe
 *      live, AWS, GitHub, Slack, SendGrid, private key blocks).
 *   2. Secret-bearing files tracked by git (.env with values, private keys,
 *      Apple .p8, service-account JSON) — the classic "committed .env".
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

function checkSourceKeys(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  for (const file of files) {
    for (const { re, label } of KEY_PATTERNS) {
      re.lastIndex = 0
      let m: RegExpExecArray | null
      while ((m = re.exec(file.text))) {
        if (PLACEHOLDER.test(m[0])) continue
        findings.push({
          check: 'hardcoded-secrets',
          severity: 'finding',
          file: file.relPath,
          line: lineNumberAt(file.text, m.index),
          message: `${label} hardcoded in source ("${redact(m[0])}") — anyone with the repo or the bundle can use it. Move it to an env var and rotate the key.`,
          fixHint: 'open-editor',
        })
      }
    }
  }
  return findings
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

function gitTrackedFiles(root: string): string[] {
  try {
    const out = execFileSync('git', ['-C', root, 'ls-files', '-z'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 10_000,
      maxBuffer: 64 * 1024 * 1024,
    })
    return out.split('\0').filter(Boolean)
  } catch {
    return [] // not a git repo, or git missing — nothing tracked to judge
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

/**
 * Secret-bearing files committed to git. `prefix` is the label the scan uses
 * for companion roots so paths line up with the rest of the report.
 */
export function checkTrackedSecretFiles(root: string, prefix = ''): Finding[] {
  const findings: Finding[] = []
  for (const rel of gitTrackedFiles(root)) {
    const name = basename(rel)
    const file = prefix ? join(prefix, rel) : rel

    if (ENV_FILE.test(name) && !ENV_TEMPLATE.test(name)) {
      if (!envHasValues(readSafe(join(root, rel)))) continue
      const lowRisk = ENV_LOW_RISK.test(name)
      findings.push({
        check: 'hardcoded-secrets',
        severity: lowRisk ? 'warning' : 'finding',
        file,
        message: lowRisk
          ? `${name} with values is tracked by git — fine only if nothing in it is secret.`
          : `${name} with values is tracked by git — every secret in it is in your history. Untrack it (git rm --cached), add it to .gitignore, and rotate what was in it.`,
        fixHint: 'open-editor',
      })
      continue
    }

    for (const rule of TRACKED_RULES) {
      if (!rule.test(name)) continue
      if (rule.needs && !rule.needs.test(readSafe(join(root, rel)))) continue
      findings.push({
        check: 'hardcoded-secrets',
        severity: 'finding',
        file,
        message: `${rule.label} is tracked by git — it's in your history even if deleted later. Untrack it, add it to .gitignore, and rotate it.`,
        fixHint: 'open-editor',
      })
      break
    }
  }
  return findings
}

export function checkSecrets(files: SourceFile[]): Finding[] {
  return checkSourceKeys(files)
}
