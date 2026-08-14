import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

export type FixResult = {
  ok: boolean
  file: string
  message: string
  before?: string
  after?: string
}

/**
 * Safe fix for dead-exports: strip the `export` keyword from the declaration
 * at the given line, leaving the function/const in place for local use.
 */
export function fixRemoveExport(repoRoot: string, relPath: string, line: number): FixResult {
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

  const original = lines[idx]
  // export async function X / export function X / export const X / export class X
  const next = original.replace(
    /^(\s*)export\s+(?=async\s+function|function|const|let|class|type|interface)/,
    '$1',
  )

  if (next === original) {
    // Brace-list export form — comment the line out (safe, reversible).
    // Phrase split so dead-exports regex doesn't treat this string as an export list.
    const listStrip = original.replace(/^(\s*)export\s+\{/, `$1// was: ${'export'} {`)
    if (listStrip !== original) {
      lines[idx] = listStrip
      const after = lines.join('\n')
      writeFileSync(abs, after, 'utf8')
      return {
        ok: true,
        file: relPath,
        message: `Commented export list at line ${line}`,
        before: original,
        after: listStrip,
      }
    }
    return { ok: false, file: relPath, message: `No removable export on line ${line}` }
  }

  lines[idx] = next
  const after = lines.join('\n')
  writeFileSync(abs, after, 'utf8')
  return {
    ok: true,
    file: relPath,
    message: `Removed export keyword at line ${line}`,
    before: original,
    after: next,
  }
}
