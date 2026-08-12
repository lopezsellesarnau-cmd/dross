import { readdirSync, statSync, readFileSync } from 'node:fs'
import { join, relative } from 'node:path'

const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'])

// Directories that are never source code, even in a repo that doesn't
// gitignore them consistently (build output, vendored deps, VCS internals).
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', '.next', '.expo', 'coverage', 'Pods'])

export type SourceFile = { absPath: string; relPath: string; text: string }

/** Walks a repo root and returns every source file's path + contents.
 *  No .gitignore parsing yet (v1) — SKIP_DIRS covers the common cases;
 *  a real .gitignore reader is a fast-follow, not a blocker for the first
 *  check to be useful. */
export function collectSourceFiles(repoRoot: string): SourceFile[] {
  const files: SourceFile[] = []

  function walk(dir: string) {
    let entries: string[]
    try {
      entries = readdirSync(dir)
    } catch {
      return // permission-denied or race with a deleted dir — skip, don't crash the scan
    }
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry)) continue
      const abs = join(dir, entry)
      let stat
      try {
        stat = statSync(abs)
      } catch {
        continue
      }
      if (stat.isDirectory()) {
        walk(abs)
        continue
      }
      const ext = entry.slice(entry.lastIndexOf('.'))
      if (!SOURCE_EXTENSIONS.has(ext)) continue
      files.push({ absPath: abs, relPath: relative(repoRoot, abs), text: readFileSafe(abs) })
    }
  }

  walk(repoRoot)
  return files
}

function readFileSafe(path: string): string {
  try {
    return readFileSync(path, 'utf8')
  } catch {
    return ''
  }
}
