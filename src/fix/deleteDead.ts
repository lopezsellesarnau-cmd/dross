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
 * Delete a top-level declaration that starts on `line` (1-based).
 * Handles: export function / async function / const / let / class / type / interface
 * and their non-export forms. Uses brace/paren matching — verified, not LLM.
 */
export function fixDeleteDead(repoRoot: string, relPath: string, line: number): FixResult {
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

  const startLine = lines[idx]
  if (
    !/^\s*(export\s+)?(async\s+)?function\b/.test(startLine) &&
    !/^\s*(export\s+)?(const|let|class|type|interface)\b/.test(startLine)
  ) {
    return {
      ok: false,
      file: relPath,
      message: `Line ${line} isn’t a deletable declaration (function/const/class/type)`,
    }
  }

  // Walk forward collecting a balanced block.
  let endIdx = idx
  let brace = 0
  let paren = 0
  let bracket = 0
  let started = false
  let inStr: string | null = null

  const slice = lines.slice(idx).join('\n')
  for (let i = 0; i < slice.length; i++) {
    const ch = slice[i]
    const prev = slice[i - 1]

    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
      continue
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inStr = ch
      continue
    }
    if (ch === '{') {
      brace++
      started = true
    } else if (ch === '}') {
      brace--
    } else if (ch === '(') {
      paren++
      started = true
    } else if (ch === ')') {
      paren--
    } else if (ch === '[') {
      bracket++
      started = true // export const X = [ … ] must delete the whole array, not just the header line
    } else if (ch === ']') {
      bracket--
    }

    // const x = 1  (no braces) — end at semicolon or newline once we're past =
    if (!started && /=\s*[^({\[]/.test(startLine) && (ch === ';' || ch === '\n')) {
      // find which line we're on
      const consumed = slice.slice(0, i + 1)
      endIdx = idx + consumed.split('\n').length - 1
      break
    }

    if (started && brace <= 0 && paren <= 0 && bracket <= 0) {
      const consumed = slice.slice(0, i + 1)
      endIdx = idx + consumed.split('\n').length - 1
      // swallow trailing semicolon on same or next short line
      if (endIdx + 1 < lines.length && /^\s*;\s*$/.test(lines[endIdx + 1])) endIdx++
      break
    }
  }

  if (endIdx < idx) {
    return { ok: false, file: relPath, message: `Could not find end of declaration at ${line}` }
  }

  const before = lines.slice(idx, endIdx + 1).join('\n')
  // Drop one surrounding blank line for cleanliness
  let from = idx
  let to = endIdx
  if (from > 0 && lines[from - 1].trim() === '') from--
  else if (to + 1 < lines.length && lines[to + 1].trim() === '') to++

  const removed = lines.splice(from, to - from + 1)
  writeFileSync(abs, lines.join('\n'), 'utf8')
  return {
    ok: true,
    file: relPath,
    message: `Deleted dead declaration at lines ${from + 1}–${to + 1}`,
    before: removed.join('\n'),
    after: '',
  }
}
