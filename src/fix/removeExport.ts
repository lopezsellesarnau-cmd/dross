import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { nearbyDeclarationIndex } from './nearbyDeclaration.js'

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
  const reportedIdx = line - 1
  if (reportedIdx < 0 || reportedIdx >= lines.length) {
    return { ok: false, file: relPath, message: `Line ${line} out of range` }
  }
  // Same staleness tolerance as deleteDead — fall back to the reported line
  // if nothing declaration-shaped is nearby, so the existing "no removable
  // export" / "already fixed" messages below still apply as before.
  const idx = nearbyDeclarationIndex(lines, reportedIdx) ?? reportedIdx

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
