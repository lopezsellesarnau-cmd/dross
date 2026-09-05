import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { stripComments } from '../stripComments.js'

/**
 * Env drift — classic vibecoder deploy fail: code reads process.env.FOO
 * (or Vite/Next public env) but FOO never appears in .env.example / .env*.
 * Deterministic; no guesses.
 */

const ENV_ACCESS =
  /(?:process\.env|import\.meta\.env|Deno\.env\.get)\s*(?:\.([A-Z][A-Z0-9_]*)|\(\s*['"`]([A-Z][A-Z0-9_]*)['"`]\s*\))/g

const ENV_FILE_NAMES = [
  '.env.example',
  '.env.sample',
  '.env.template',
  '.env',
  '.env.local',
  '.env.development',
  '.env.development.local',
  '.env.production',
]

/** Built-ins / framework noise — never flag these. */
const IGNORE = new Set([
  'NODE_ENV',
  'PATH',
  'HOME',
  'USER',
  'SHELL',
  'TMPDIR',
  'PWD',
  'LANG',
  'TERM',
  'CI',
  'PORT', // injected by Render/Heroku/etc. — almost never in .env.example
  'VERCEL',
  'VERCEL_URL',
  'VERCEL_ENV',
  'NEXT_RUNTIME',
  'NEXT_PHASE',
])

function lineNumberAt(text: string, index: number): number {
  let line = 1
  for (let i = 0; i < index && i < text.length; i++) {
    if (text.charCodeAt(i) === 10) line++
  }
  return line
}

function parseEnvFile(abs: string): Set<string> {
  const keys = new Set<string>()
  let text: string
  try {
    text = readFileSync(abs, 'utf8')
  } catch {
    return keys
  }
  for (const raw of text.split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    const m = line.match(/^(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=/)
    if (m) keys.add(m[1])
  }
  return keys
}

function collectDeclaredEnv(repoRoot: string): { keys: Set<string>; files: string[] } {
  const keys = new Set<string>()
  const files: string[] = []
  for (const name of ENV_FILE_NAMES) {
    const abs = join(repoRoot, name)
    if (!existsSync(abs)) continue
    files.push(name)
    for (const k of parseEnvFile(abs)) keys.add(k)
  }
  return { keys, files }
}

export function checkEnvDrift(repoRoot: string, files: SourceFile[]): Finding[] {
  const { keys: declared, files: envFiles } = collectDeclaredEnv(repoRoot)
  // No env files at all — still report vars used (severity warning): vibecoder
  // often deploys with secrets only in the host UI and forgets .env.example.
  const findings: Finding[] = []
  const seen = new Set<string>()

  for (const file of files) {
    if (/\.(test|spec)\.[jt]sx?$/.test(file.relPath)) continue
    const code = stripComments(file.text)
    ENV_ACCESS.lastIndex = 0
    let m: RegExpExecArray | null
    while ((m = ENV_ACCESS.exec(code))) {
      const name = m[1] || m[2]
      if (!name || IGNORE.has(name)) continue
      // NEXT_PUBLIC_ / VITE_ / EXPO_PUBLIC_ still must be documented for teammates
      if (declared.has(name)) continue
      const key = `${name}:${file.relPath}`
      if (seen.has(key)) continue
      seen.add(key)
      findings.push({
        check: 'env-drift',
        severity: envFiles.length === 0 ? 'warning' : 'finding',
        file: file.relPath,
        line: lineNumberAt(code, m.index),
        message:
          envFiles.length === 0
            ? `"${name}" is read from the environment, but this repo has no .env.example (or .env*) — deploy will fail for anyone who clones without guessing the vars.`
            : `"${name}" is read in code but missing from ${envFiles.join(', ')} — classic ship-break when the host env isn’t set.`,
        fixHint: 'add-env-example',
      })
    }
  }

  return findings
}
