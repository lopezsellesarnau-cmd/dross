import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'

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

// `export { a, b as c }` — captures the whole brace group, split separately.
const EXPORT_LIST_PATTERN = /export\s*\{([^}]+)\}\s*(?:from\s+['"][^'"]+['"])?/g

function extractExportedNames(text: string): string[] {
  const names = new Set<string>()

  for (const pattern of EXPORT_PATTERNS) {
    pattern.lastIndex = 0
    let m: RegExpExecArray | null
    while ((m = pattern.exec(text))) names.add(m[1])
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
      names.add(asMatch ? asMatch[1] : trimmed.split(/\s+/)[0])
    }
  }

  return [...names]
}

function fileBaseName(relPath: string): string {
  const slash = relPath.lastIndexOf('/')
  return slash === -1 ? relPath : relPath.slice(slash + 1)
}

export function checkDeadExports(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []

  for (const file of files) {
    if (ENTRY_POINT_FILENAMES.has(fileBaseName(file.relPath))) continue
    // Test files export helpers the test runner imports by convention in
    // some frameworks, and their "dead" exports are rarely the risk this
    // check is for — skip to cut a common noise source.
    if (/\.(test|spec)\.[jt]sx?$/.test(file.relPath)) continue

    const exported = extractExportedNames(file.text)
    for (const name of exported) {
      if (name.length <= 2) continue // too short to grep reliably without false negatives eating the signal

      const usedElsewhere = files.some((other) => {
        if (other.absPath === file.absPath) return false
        const pattern = new RegExp(`\\b${name}\\b`)
        return pattern.test(other.text)
      })
      if (usedElsewhere) continue

      // Distinguish "nothing references this at all" (real dead code) from
      // "only its own declaring file uses it" (the code runs fine, just the
      // export is pointless — a different, lower-confidence claim). Two
      // occurrences of the name in its own file means declaration + at
      // least one use; one occurrence means only the declaration exists.
      const ownFileMatches = file.text.match(new RegExp(`\\b${name}\\b`, 'g')) ?? []
      const usedWithinOwnFile = ownFileMatches.length > 1

      findings.push({
        check: 'dead-exports',
        severity: usedWithinOwnFile ? 'warning' : 'finding',
        file: file.relPath,
        message: usedWithinOwnFile
          ? `"${name}" is only used within this file — the export looks unnecessary (nothing imports it).`
          : `"${name}" is exported but not referenced anywhere in the repo, not even within its own file — likely dead code.`,
      })
    }
  }

  return findings
}
