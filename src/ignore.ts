import { readFileSync } from 'node:fs'
import { join } from 'node:path'

/**
 * `.drossignore` — paths Dross should not scan (test fixtures, sample apps,
 * vendored code). A subset of .gitignore syntax, one pattern per line:
 *
 *   eval/corpus/     a folder, relative to the scan root (a `/` inside anchors it)
 *   vendor/          any folder named `vendor`, at any depth
 *   *.min.js         any file matching the glob, at any depth
 *   /scripts/        leading `/` = only at the root
 *   # comment        blank lines and comments are ignored
 *
 * `*` matches within one path segment, `**` across segments, `?` one char.
 * Negation (`!pattern`) is not supported — such lines are ignored rather
 * than silently re-including something.
 *
 * Ignoring can hide real problems, so every report says how many paths were
 * skipped: an ignore file must never make a repo look cleaner in silence.
 */

type Rule = { re: RegExp; anchored: boolean; dirOnly: boolean }

export type IgnoreRules = {
  /** True when `relPath` (or any folder above it) is ignored. */
  ignores(relPath: string, isDir?: boolean): boolean
  patterns: string[]
}

const NO_IGNORE: IgnoreRules = { ignores: () => false, patterns: [] }

function globToRegExp(glob: string): RegExp {
  let re = ''
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i]
    if (c === '*') {
      if (glob[i + 1] === '*') {
        re += '.*'
        i++
        if (glob[i + 1] === '/') i++ // `**/` also matches zero folders
      } else {
        re += '[^/]*'
      }
    } else if (c === '?') {
      re += '[^/]'
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
    }
  }
  return new RegExp(`^${re}$`)
}

export function parseDrossIgnore(text: string): IgnoreRules {
  const rules: Rule[] = []
  const patterns: string[] = []
  for (const raw of text.split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#') || line.startsWith('!')) continue
    patterns.push(line)
    let p = line.replace(/\\/g, '/')
    const dirOnly = p.endsWith('/')
    p = p.replace(/\/+$/, '')
    const anchored = p.startsWith('/') || p.includes('/')
    p = p.replace(/^\/+/, '')
    if (!p) continue
    rules.push({ re: globToRegExp(p), anchored, dirOnly })
  }
  if (rules.length === 0) return { ...NO_IGNORE, patterns }

  const matchesOne = (candidate: string, isDir: boolean): boolean =>
    rules.some((r) => {
      if (r.dirOnly && !isDir) return false
      const subject = r.anchored ? candidate : candidate.slice(candidate.lastIndexOf('/') + 1)
      return r.re.test(subject)
    })

  return {
    patterns,
    ignores(relPath: string, isDir = false): boolean {
      const parts = relPath.replace(/\\/g, '/').split('/').filter(Boolean)
      // Every folder above the path, then the path itself.
      for (let i = 1; i <= parts.length; i++) {
        const candidate = parts.slice(0, i).join('/')
        const candidateIsDir = i < parts.length || isDir
        if (matchesOne(candidate, candidateIsDir)) return true
      }
      return false
    },
  }
}

/** Rules from `<root>/.drossignore`, or none when the file doesn't exist. */
export function loadDrossIgnore(root: string): IgnoreRules {
  try {
    return parseDrossIgnore(readFileSync(join(root, '.drossignore'), 'utf8'))
  } catch {
    return NO_IGNORE
  }
}
