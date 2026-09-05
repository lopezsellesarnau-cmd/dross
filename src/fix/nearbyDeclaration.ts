const DECL_PATTERN = /^\s*(export\s+)?(async\s+)?function\b|^\s*(export\s+)?(const|let|class|type|interface)\b/

/**
 * Finds the nearest line matching a declaration within `window` lines
 * either side of `idx` (checking `idx` itself first). Mirrors the Swift
 * app's VerifiedFixer.nearbyDeclarationIndex — a finding's reported line
 * drifts when the file changes after the scan that produced it ran (a
 * leading comment or blank line added above the declaration shifts
 * everything below), and failing outright on an exact-line mismatch turns
 * a routine "file moved on since your last scan" into a dead end instead
 * of just finding the declaration a couple of lines away.
 */
export function nearbyDeclarationIndex(lines: string[], idx: number, window = 3): number | null {
  if (idx < 0 || idx >= lines.length) return null
  if (DECL_PATTERN.test(lines[idx])) return idx
  for (let offset = 1; offset <= window; offset++) {
    for (const candidate of [idx + offset, idx - offset]) {
      if (candidate >= 0 && candidate < lines.length && DECL_PATTERN.test(lines[candidate])) {
        return candidate
      }
    }
  }
  return null
}
