import { writeFileSync } from 'node:fs'
import type { FixResult } from './removeExport.js'

/**
 * Write a fixed file. Returns a failed FixResult when the write didn't
 * happen (permissions, disk full, file gone) — a fix must never be reported
 * as applied unless it reached the disk. Null = written.
 */
export function writeFix(abs: string, text: string, relPath: string): FixResult | null {
  try {
    writeFileSync(abs, text, 'utf8')
    return null
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err)
    return { ok: false, file: relPath, message: `Could not write ${relPath}: ${reason}` }
  }
}
