import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import type { FixResult } from './removeExport.js'

const ENV_ACCESS =
  /(?:process\.env|import\.meta\.env|Deno\.env\.get)\s*(?:\.([A-Z][A-Z0-9_]*)|\(\s*['"`]([A-Z][A-Z0-9_]*)['"`]\s*\))/

/**
 * Safe env-drift fix: document the missing var in `.env.example` (empty
 * value — never copies secrets from .env). Creates the file if needed.
 */
export function fixAddEnvExample(repoRoot: string, relPath: string, line: number): FixResult {
  const abs = resolve(repoRoot, relPath)
  let text: string
  try {
    text = readFileSync(abs, 'utf8')
  } catch {
    return { ok: false, file: relPath, message: `Could not read ${relPath}` }
  }
  const lines = text.split('\n')
  const idx = line - 1
  if (idx < 0 || idx >= lines.length) {
    return { ok: false, file: relPath, message: `Line ${line} out of range` }
  }
  const m = lines[idx].match(ENV_ACCESS)
  const name = m?.[1] || m?.[2]
  if (!name) {
    return { ok: false, file: relPath, message: `No env access on line ${line}` }
  }

  const examplePath = resolve(repoRoot, '.env.example')
  let existing = ''
  if (existsSync(examplePath)) {
    existing = readFileSync(examplePath, 'utf8')
    if (new RegExp(`^(?:export\\s+)?${name}\\s*=`, 'm').test(existing)) {
      return { ok: true, file: '.env.example', message: `${name} already in .env.example` }
    }
  }
  const prefix = existing && !existing.endsWith('\n') ? '\n' : existing ? '' : ''
  const next = `${existing}${prefix}${name}=\n`
  writeFileSync(examplePath, next, 'utf8')
  return {
    ok: true,
    file: '.env.example',
    message: `Documented ${name} in .env.example (empty — set the real value on the host).`,
    before: existing,
    after: next,
  }
}
