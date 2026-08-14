/**
 * Cheap comment stripper for regex-based checks. Not a full parser —
 * removes line comments and block comments so example strings in
 * JSDoc do not look like real exports or HTTP calls.
 * Line numbers stay aligned because newlines are preserved.
 */
export function stripComments(source: string): string {
  let out = ''
  let i = 0
  const n = source.length
  while (i < n) {
    const c = source[i]
    const next = source[i + 1]

    // string literals — keep intact so we don't eat // inside strings
    if (c === '"' || c === "'" || c === '`') {
      const quote = c
      out += c
      i++
      while (i < n) {
        if (source[i] === '\\') {
          out += source[i] + (source[i + 1] ?? '')
          i += 2
          continue
        }
        out += source[i]
        if (source[i] === quote) {
          i++
          break
        }
        i++
      }
      continue
    }

    if (c === '/' && next === '/') {
      while (i < n && source[i] !== '\n') {
        out += ' '
        i++
      }
      continue
    }

    if (c === '/' && next === '*') {
      out += '  '
      i += 2
      while (i < n - 1 && !(source[i] === '*' && source[i + 1] === '/')) {
        out += source[i] === '\n' ? '\n' : ' '
        i++
      }
      if (i < n - 1) {
        out += '  '
        i += 2
      }
      continue
    }

    out += c
    i++
  }
  return out
}
