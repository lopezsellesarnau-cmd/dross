# Dross

Scans a repo before you deploy and reports dead code, contradictions, and
**contract drift** between frontend and backend — bugs that look fine because
they're meaning errors, not syntax errors.

## Status

v1 in progress. Deterministic checks + SwiftUI Mac app + CLI for CI.

## CLI (CI)

```bash
npm install
npm run build

# Scan — exit 1 if findings (CI-friendly)
npx dross scan . --json
# shortcut (same as scan):
npx dross .

# Split client + API (TRACE-class) — required for contract-drift across packages
npx dross scan ./trace-app --also ./trace-backend --json

# Human-readable:
npx dross scan ./apps/web

# Verified autofix (dead exports)
npx dross fix . path/to/file.ts 42 remove-export

# Mute a finding so it no longer fails CI (stores in .dross/memory.json)
npx dross mute . helpers.ts 4 --reason "exported for a plugin"
npx dross unmute . helpers.ts 4
```

`.dross/memory.json` is **per-user by default** — add `.dross/` to `.gitignore` unless the team wants to share mute/acknowledge decisions in git.

GitHub Actions sketch:

```yaml
- run: npm ci && npm run build
- run: npx dross scan . --json
# or: npx dross scan ./apps/mobile --also ./services/api --json
```

Optional LLM drift pass: set `ANTHROPIC_API_KEY`.

## Mac app

```bash
cd app && ./rebuild.sh
```

Flow: Welcome → local auth stub → onboarding → **open repo** (folder picker) →
scan → detail. Auth is a **local stub** in v1 (Continue locally / fake sign-in);
nothing leaves the Mac. Cloud auth is deferred.

The detail view uses the same memory file as the CLI (`.dross/memory.json`).
**Ignore** in the fix panel mutes a finding. High-confidence findings show by
default; low-confidence ones sit behind “N low”. Regressions (fixed, then back)
are tagged `↻`.

## Packaging (DMG)

```bash
# Dev DMG (unsigned)
./scripts/package-dmg.sh

# Release (Developer ID + notarytool profile in Keychain)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE_PROFILE="notarytool-profile" \
VERSION=0.1.0 \
  ./scripts/package-dmg.sh
```

Output: `dist-release/Dross-<version>.dmg`. Certs never live in the repo.

You already have signing material on the Mac (`*.p12`); import into Keychain,
then `security find-identity -v -p codesigning` to copy the exact
`SIGN_IDENTITY` string. Notarization still needs an Apple ID app-specific
password stored via `xcrun notarytool store-credentials`.

## Architecture

TypeScript engine (`src/`) → JSON report. SwiftUI app shells out to the bundled
engine. Same CLI for local and CI. Deterministic checks first; optional LLM only
for semantic drift when a key is present.

Checks: `dead-exports`, `contract-drift`, `env-drift`, `todo-density`,
`hardcoded-demo`. Autofix: `remove-export`, `delete-dead`.
