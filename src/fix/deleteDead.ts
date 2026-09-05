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
  const reportedIdx = line - 1
  if (reportedIdx < 0 || reportedIdx >= lines.length) {
    return { ok: false, file: relPath, message: `Line ${line} out of range` }
  }

  const idx = nearbyDeclarationIndex(lines, reportedIdx)
  if (idx === null) {
    return {
      ok: false,
      file: relPath,
      message: `Line ${line} isn’t a deletable declaration (function/const/class/type)`,
    }
  }
  const startLine = lines[idx]

  // Walk forward collecting a balanced block.
  let endIdx = idx
  // Single combined depth, not three independent counters — a function's
  // parameter list can contain its own fully-balanced braces (destructuring,
  // inline type annotations: `({ step }: { step: 1|2|3 })`), which brings
  // brace count back to 0 — together with paren count also reaching 0 as
  // the parameter list's `)` closes — *before* the body has even opened.
  // Three independent counters treated that coincidence as "declaration
  // complete" and truncated the deletion to just the signature line,
  // leaving the body orphaned in the file. A close only counts as the real
  // end once depth returns to 0 via `}` (a body/block closing) or `;` (a
  // brace-less declaration ending) — never via `)` or `]` alone, since
  // those close argument/param/index groups that can have more to follow.
  let depth = 0
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
    if (ch === '{' || ch === '(' || ch === '[') {
      depth++
      started = true
    } else if (ch === '}' || ch === ')' || ch === ']') {
      depth--
    }

    if (started && depth <= 0 && (ch === '}' || ch === ';')) {
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
