import { readdirSync, lstatSync, readFileSync } from 'node:fs'
import { join, relative } from 'node:path'

const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'])

// Directories that are never source code, even in a repo that doesn't
// gitignore them consistently (build output, vendored deps, VCS internals).
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', '.next', '.expo', 'coverage', 'Pods'])

// Scanning $HOME (or any directory that isn't actually a single repo) can
// walk into caches with tens of thousands of files (~/.npm, ~/.cache,
// editor extension folders) and OOM the process — reproduced this hitting
// 4GB+ heap. A hard cap turns "crash with no output" into "bounded scan
// with a clear truncation notice," which is the honest failure mode: no
// silent partial coverage presented as complete.
const MAX_FILES = 8000

export type SourceFile = { absPath: string; relPath: string; text: string }
export type CollectResult = { files: SourceFile[]; truncated: boolean }

/** Walks a repo root and returns every source file's path + contents.
 *  No .gitignore parsing yet (v1) — SKIP_DIRS covers the common cases;
 *  a real .gitignore reader is a fast-follow, not a blocker for the first
 *  check to be useful. */
export function collectSourceFiles(repoRoot: string): CollectResult {
  const files: SourceFile[] = []
  let truncated = false

  function walk(dir: string) {
    if (truncated) return
    let entries: string[]
    try {
      entries = readdirSync(dir)
    } catch {
      return // permission-denied or race with a deleted dir — skip, don't crash the scan
    }
    for (const entry of entries) {
      if (truncated) return
      // Dotfiles/dot-directories (.cache, .npm, .vscode, editor state) are
      // never project source and are exactly what turns "scan a repo" into
      // "scan $HOME and OOM" if someone points this at the wrong directory.
      if (entry.startsWith('.')) continue
      if (SKIP_DIRS.has(entry)) continue
      const abs = join(dir, entry)
      let stat
      try {
        stat = lstatSync(abs) // lstat, not stat — a followed symlink cycle would recurse forever
      } catch {
        continue
      }
      if (stat.isSymbolicLink()) continue
      if (stat.isDirectory()) {
        walk(abs)
        continue
      }
      const ext = entry.slice(entry.lastIndexOf('.'))
      if (!SOURCE_EXTENSIONS.has(ext)) continue
      if (files.length >= MAX_FILES) {
        truncated = true
        return
      }
      files.push({ absPath: abs, relPath: relative(repoRoot, abs), text: readFileSafe(abs) })
    }
  }

  walk(repoRoot)
  return { files, truncated }
}

function readFileSafe(path: string): string {
  try {
    return readFileSync(path, 'utf8')
  } catch {
    return ''
  }
}
