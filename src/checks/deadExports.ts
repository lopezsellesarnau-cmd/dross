import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { stripComments } from '../stripComments.js'

/**
 * Heuristic, not full AST: regex-extracts named exports and greps for the
 * identifier elsewhere in the repo. Good enough to be useful for v1 — the
 * real target isn't "0% false positives", it's "catches the TRACE /notify
 * case" (an endpoint with a valid signature that nothing calls). A proper
 * tree-sitter/ast-grep pass replaces this once the check pipeline proves
 * out; regex first, because a check nobody runs because it's not built yet
 * catches nothing.
 */

// Framework entry points are exported but never *imported* by name — a
// router/build tool calls them by file path or convention, not by
// identifier. Flagging these would be the single most common false
// positive, so filenames matching these conventions are skipped entirely.
const ENTRY_POINT_FILENAMES = new Set([
  'index.ts', 'index.tsx', 'index.js', 'index.jsx',
  'main.ts', 'main.tsx',
  'cli.ts', 'server.ts',
  'app.tsx', 'app.ts',
  'layout.tsx', 'page.tsx', 'route.ts', 'route.tsx',
  '_app.tsx', '_document.tsx', 'middleware.ts',
])

const EXPORT_PATTERNS = [
  /export\s+(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/g,
  /export\s+const\s+([A-Za-z_$][\w$]*)/g,
  /export\s+let\s+([A-Za-z_$][\w$]*)/g,
  /export\s+class\s+([A-Za-z_$][\w$]*)/g,
]

// `export { a, b as c }` — one line, identifier-only parts (avoids matching
// `export {` inside regex/string examples that later close with an unrelated `}`).
const EXPORT_LIST_PATTERN =
  /(?:^|[;\n])\s*export\s*\{\s*([A-Za-z_$][\w$\s,]*(?:\s+as\s+[A-Za-z_$][\w$]*)?(?:\s*,\s*[A-Za-z_$][\w$\s]*(?:\s+as\s+[A-Za-z_$][\w$]*)?)*)\s*\}\s*(?:from\s+['"][^'"]+['"])?/gm

type ExportedName = { name: string; index: number }

function extractExportedNames(text: string): ExportedName[] {
  // First occurrence per name wins the line number — a name can only be
  // declared once as an export in valid source, so this is the declaration
  // site, which is what the code-preview panel needs to jump to.
  const byName = new Map<string, number>()
  const record = (name: string, index: number) => {
    if (!byName.has(name)) byName.set(name, index)
  }

  for (const pattern of EXPORT_PATTERNS) {
    pattern.lastIndex = 0
    let m: RegExpExecArray | null
    while ((m = pattern.exec(text))) record(m[1], m.index)
  }

  EXPORT_LIST_PATTERN.lastIndex = 0
  let listMatch: RegExpExecArray | null
  while ((listMatch = EXPORT_LIST_PATTERN.exec(text))) {
    for (const part of listMatch[1].split(',')) {
      // `a as b` exports `b`; a bare `a` exports `a`. `default as X` is a
      // default re-export — skip it, same reason plain `export default` is skipped.
      const trimmed = part.trim()
      if (!trimmed || trimmed.startsWith('default')) continue
      const asMatch = trimmed.match(/\bas\s+([A-Za-z_$][\w$]*)/)
      record(asMatch ? asMatch[1] : trimmed.split(/\s+/)[0], listMatch.index)
    }
  }

  return [...byName.entries()].map(([name, index]) => ({ name, index }))
}

function lineNumberAt(text: string, index: number): number {
  let line = 1
  for (let i = 0; i < index && i < text.length; i++) {
    if (text.charCodeAt(i) === 10) line++
  }
  return line
}

function fileBaseName(relPath: string): string {
  const slash = relPath.lastIndexOf('/')
  return slash === -1 ? relPath : relPath.slice(slash + 1)
}

// Every identifier-shaped token in the file, once. Reused for both "does
// this name appear in this file" and "how many times" — the two questions
// the check actually needs — without re-running a fresh regex per name.
const TOKEN_PATTERN = /[A-Za-z_$][\w$]*/g

function tokenCounts(text: string): Map<string, number> {
  const counts = new Map<string, number>()
  TOKEN_PATTERN.lastIndex = 0
  let m: RegExpExecArray | null
  while ((m = TOKEN_PATTERN.exec(text))) {
    counts.set(m[0], (counts.get(m[0]) ?? 0) + 1)
  }
  return counts
}

/**
 * Was O(exports × files), re-scanning every other file's full text with a
 * fresh RegExp per exported name — measured hanging past 45s / ballooning
 * to 4GB+ heap on a few thousand files. Now one tokenization pass per file
 * (O(total source size)), then each export is a map lookup per file
 * (O(exports × files) lookups, but O(1) each, not O(filesize) each) —
 * the same check, correctly bounded.
 */
export function checkDeadExports(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  const tokensByFile = new Map(files.map((f) => [f.absPath, tokenCounts(f.text)]))

  for (const file of files) {
    if (ENTRY_POINT_FILENAMES.has(fileBaseName(file.relPath))) continue
    // Test files export helpers the test runner imports by convention in
    // some frameworks, and their "dead" exports are rarely the risk this
    // check is for — skip to cut a common noise source.
    if (/\.(test|spec)\.[jt]sx?$/.test(file.relPath)) continue

    const code = stripComments(file.text)
    const exported = extractExportedNames(code)
    for (const { name, index } of exported) {
      // Identifiers only — reject junk from malformed regex hits.
      if (!/^[A-Za-z_$][\w$]*$/.test(name) || name.length <= 2) continue

      const usedElsewhere = files.some(
        (other) => other.absPath !== file.absPath && (tokensByFile.get(other.absPath)?.get(name) ?? 0) > 0,
      )
      if (usedElsewhere) continue

      // Distinguish "nothing references this at all" (real dead code) from
      // "only its own declaring file uses it" (the code runs fine, just the
      // export is pointless — a different, lower-confidence claim). Two
      // occurrences of the name in its own file means declaration + at
      // least one use; one occurrence means only the declaration exists.
      const ownFileCount = tokensByFile.get(file.absPath)?.get(name) ?? 0
      const usedWithinOwnFile = ownFileCount > 1

      findings.push({
        check: 'dead-exports',
        severity: usedWithinOwnFile ? 'warning' : 'finding',
        file: file.relPath,
        line: lineNumberAt(code, index),
        message: usedWithinOwnFile
          ? `"${name}" is only used within this file — the export looks unnecessary (nothing imports it).`
          : `"${name}" is exported but not referenced anywhere in the repo, not even within its own file — likely dead code.`,
        // Fully unused → delete declaration. Local-only export → strip keyword.
        fixHint: usedWithinOwnFile ? 'remove-export' : 'delete-dead',
      })
    }
  }

  return findings
}
