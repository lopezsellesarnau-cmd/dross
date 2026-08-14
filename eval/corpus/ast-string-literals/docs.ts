// A help/docs module whose STRINGS contain route- and fetch-shaped text.
// These are examples in prose, not real calls — a regex on the source sees
// `app.post(...)` / `fetch(...)` and invents phantom endpoints; a real parser
// knows they live inside string literals and ignores them.
export const helpText = [
  'Legacy API (removed — do not call):',
  "  server used to expose app.post('/legacy/register')",
  "  the old client did fetch('/legacy/ping')",
].join('\n')
