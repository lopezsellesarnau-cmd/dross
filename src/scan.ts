import { readdirSync, lstatSync, readFileSync } from 'node:fs'
import { basename, join, relative } from 'node:path'

const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'])

// Directories that are never source code, even in a repo that doesn't
// gitignore them consistently (build output, vendored deps, VCS internals).
const SKIP_DIRS = new Set([
  'node_modules',
  '.git',
  'dist',
  'build',
  '.next',
  '.expo',
  'coverage',
  'Pods',
  '.build',
])

// Scanning $HOME (or any directory that isn't actually a single repo) can
// walk into caches with tens of thousands of files (~/.npm, ~/.cache,
// editor extension folders) and OOM the process — reproduced this hitting
// 4GB+ heap. A hard cap turns "crash with no output" into "bounded scan
// with a clear truncation notice," which is the honest failure mode: no
// silent partial coverage presented as complete.
const MAX_FILES = 8000

export type SourceFile = {
  absPath: string
  relPath: string
  text: string
  /** Owning scan root — set when scanning multiple packages (client + API). */
  root?: string
}
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
      // macOS app bundles (incl. our own Dross.app with a copied engine)
      if (entry.endsWith('.app')) continue
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

/**
 * Union several package roots (e.g. `trace-app` + `trace-backend`) so
 * contract-drift can see both sides.
 *
 * Primary root (index 0) keeps unprefixed rel-paths so the Mac app / fix CLI
 * can resolve files against the folder the user opened. Companion roots get
 * a basename prefix (`trace-backend/src/…`).
 */
export function collectSourceFilesMulti(roots: string[]): CollectResult {
  if (roots.length === 0) return { files: [], truncated: false }
  if (roots.length === 1) {
    const one = collectSourceFiles(roots[0])
    return {
      files: one.files.map((f) => ({ ...f, root: roots[0] })),
      truncated: one.truncated,
    }
  }

  const files: SourceFile[] = []
  let truncated = false
  const usedLabels = new Map<string, number>()

  for (let i = 0; i < roots.length; i++) {
    const root = roots[i]
    const part = collectSourceFiles(root)
    if (part.truncated) truncated = true

    let prefix = ''
    if (i > 0) {
      const base = basename(root) || 'pkg'
      const n = (usedLabels.get(base) ?? 0) + 1
      usedLabels.set(base, n)
      prefix = n === 1 ? base : `${base}-${n}`
    }

    for (const f of part.files) {
      files.push({
        ...f,
        relPath: prefix ? join(prefix, f.relPath) : f.relPath,
        root,
      })
      if (files.length >= MAX_FILES) {
        truncated = true
        return { files, truncated }
      }
    }
  }
  return { files, truncated }
}

function readFileSafe(path: string): string {
  try {
    return readFileSync(path, 'utf8')
  } catch {
    return ''
  }
}
