import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { stripComments } from '../stripComments.js'

/**
 * Hardcoded demo / placeholder data that looks real in production UIs —
 * the Aithority class of bug (stamped dates + fake people).
 *
 * Pattern literals are assembled from parts so this check file does not
 * flag itself.
 */

type Pattern = { re: RegExp; label: string }

const PATTERNS: Pattern[] = [
  {
    re: new RegExp(`\\b(?:${['lorem', 'ipsum'].join(' ')}|${['dolor', 'sit', 'amet'].join(' ')})\\b`, 'gi'),
    label: 'lorem placeholder copy',
  },
  {
    re: new RegExp(
      `\\b(?:${['john', 'doe'].join('\\s+')}|${['jane', 'doe'].join('\\s+')}|${['marta', 'soler'].join('\\s+')}|${['test', 'user'].join('\\s+')})\\b`,
      'gi',
    ),
    label: 'placeholder person name',
  },
  { re: /\b[\w.+-]+@example\.com\b/gi, label: 'example.com email' },
  { re: /\b(?:555[- ]?0?10|555[- ]?01\d{2})\b/g, label: 'placeholder phone' },
  { re: /['"`](\d{2}\.\d{2}\.\d{4}\s*[·•]\s*\d{2}:\d{2})['"`]/g, label: 'hardcoded timestamp stamp' },
  { re: /['"`](19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])[ T]\d{2}:\d{2}['"`]/g, label: 'hardcoded datetime string' },
]

function lineNumberAt(text: string, index: number): number {
  let line = 1
  for (let i = 0; i < index && i < text.length; i++) {
    if (text.charCodeAt(i) === 10) line++
  }
  return line
}

/** `placeholder="Jane Doe"` / `placeholder='you@example.com'` — UI chrome, not shipped data. */
function isPlaceholderProp(code: string, matchIndex: number): boolean {
  const before = code.slice(Math.max(0, matchIndex - 48), matchIndex)
  return /placeholder\s*=\s*['"`]\s*$/i.test(before)
}

/** Rough: match sits inside a `__DEV__ ? (…)` branch — screenshot helpers, not prod. */
function isDevOnlyBranch(code: string, matchIndex: number): boolean {
  const window = code.slice(Math.max(0, matchIndex - 220), matchIndex)
  return /__DEV__\s*\?/.test(window)
}

export function checkHardcodedDemo(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  for (const file of files) {
    if (/\.(test|spec|mock|fixture)\.[jt]sx?$/.test(file.relPath)) continue
    if (/\/(fixtures?|mocks?|__mocks__|stories)\//i.test(file.relPath)) continue

    const code = stripComments(file.text)
    for (const { re, label } of PATTERNS) {
      re.lastIndex = 0
      let m: RegExpExecArray | null
      while ((m = re.exec(code))) {
        if (isPlaceholderProp(code, m.index)) continue
        if (isDevOnlyBranch(code, m.index)) continue
        findings.push({
          check: 'hardcoded-demo',
          severity: 'finding',
          file: file.relPath,
          line: lineNumberAt(code, m.index),
          message: `Looks like ${label} baked into source ("${m[0].slice(0, 48)}") — may ship as fake real data.`,
          fixHint: 'open-editor',
        })
        break
      }
    }
  }
  return findings
}
