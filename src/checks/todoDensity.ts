import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { stripComments } from '../stripComments.js'

// Built from parts so this file doesn't trip its own density threshold.
const MARKERS = ['TO' + 'DO', 'FIX' + 'ME', 'HA' + 'CK', 'X'.repeat(3)]
const MARKER = new RegExp(`\\b(${MARKERS.join('|')})\\b`, 'g')

/** Files dense with unresolved-work markers — ship risk if they land. */
export function checkTodoDensity(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  for (const file of files) {
    if (/\.(test|spec)\.[jt]sx?$/.test(file.relPath)) continue
    const code = stripComments(file.text)
    MARKER.lastIndex = 0
    const hits: { marker: string; index: number }[] = []
    let m: RegExpExecArray | null
    while ((m = MARKER.exec(code))) {
      hits.push({ marker: m[1], index: m.index })
    }
    if (hits.length < 3) continue // one or two is normal; density is the signal

    let line = 1
    for (let i = 0; i < hits[0].index; i++) if (code.charCodeAt(i) === 10) line++

    findings.push({
      check: 'todo-density',
      severity: hits.length >= 6 ? 'finding' : 'warning',
      file: file.relPath,
      line,
      message: `${hits.length} unresolved-work markers in this file — may ship unfinished.`,
      fixHint: 'open-editor',
    })
  }
  return findings
}
