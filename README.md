# Dross

Scans a repo before you deploy it and reports on dead code, contradictions, and
"contract drift" between frontend and backend — the bugs that look fine because
they're not syntax errors, they're meaning errors.

## Status

v1, just started. One check live: `dead-exports` (regex-heuristic, not full AST —
flags exports nothing imports, distinguishing genuinely-unreferenced code from
exports that are just unnecessary).

## Usage

```bash
npm install
npm run dev -- /path/to/repo
```

## Architecture

See the vault (`Dross/00-overview.md`) for the full plan. Short version: this
CLI is the engine; a SwiftUI Mac app will shell out to a compiled version of it
later. Deterministic checks (like this one) run free and instant; an LLM-backed
semantic/drift-detection layer comes after the deterministic layer proves out.
