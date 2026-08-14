import { existsSync, realpathSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'

/**
 * When the user opens a client package (TRACE-class: `trace-app`), also
 * pull in a sibling API package so contract-drift can see both sides.
 * Conservative: only well-known sibling names with a package.json.
 * Dedupes via realpath — critical on macOS case-insensitive volumes
 * (`trace-Backend` ≡ `trace-backend`).
 */
export function companionRoots(primary: string): string[] {
  const parent = dirname(primary)
  const base = basename(primary)
  const candidates = [primary]

  if (/-app$/i.test(base)) {
    candidates.push(join(parent, base.replace(/-app$/i, '-backend')))
    candidates.push(join(parent, base.replace(/-app$/i, '-api')))
  }
  candidates.push(join(parent, 'backend'), join(parent, 'api'), join(parent, 'server'))

  const roots: string[] = []
  const seen = new Set<string>()
  for (const c of candidates) {
    if (!existsSync(c) || !existsSync(join(c, 'package.json'))) continue
    let key = c
    try {
      key = realpathSync(c)
    } catch {
      /* keep c */
    }
    if (seen.has(key)) continue
    seen.add(key)
    roots.push(c)
  }
  return roots.length ? roots : [primary]
}
