#!/bin/bash
# Rebuilds DrossApp and repackages it into the .app bundle — the SPM
# executable + its resource bundle both need copying in, not just the
# binary, or Bundle.module lookups (the logo, drawer art) fail silently at
# runtime with no build error to catch it.
#
# Also builds the Node/TS engine and ships it at Contents/Resources/engine/
# so the app works off this checkout (Engine.swift prefers the bundle path).
set -e
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

osascript -e 'quit app "Dross"' 2>/dev/null || true
pkill -f DrossApp 2>/dev/null || true
sleep 1

# 1) Engine (CLI) — parent package
echo "Building engine…"
(cd "$ROOT" && npm run build)

# 2) Swift app
swift build

cp .build/arm64-apple-macosx/debug/DrossApp Dross.app/Contents/MacOS/DrossApp
rm -rf Dross.app/Contents/MacOS/DrossApp_DrossApp.bundle
cp -r .build/arm64-apple-macosx/debug/DrossApp_DrossApp.bundle Dross.app/Contents/MacOS/

# Dock icon — Info.plist expects CFBundleIconFile=AppIcon
mkdir -p Dross.app/Contents/Resources
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns Dross.app/Contents/Resources/AppIcon.icns
fi

# Engine into Resources/engine/ (cli.js + any sibling modules from dist/)
echo "Bundling engine into .app…"
rm -rf Dross.app/Contents/Resources/engine
mkdir -p Dross.app/Contents/Resources/engine
cp -R "$ROOT/dist/"* Dross.app/Contents/Resources/engine/
# The engine parses with the TypeScript compiler API (contract-drift AST) —
# ship the package so `import 'typescript'` resolves inside the .app too.
mkdir -p Dross.app/Contents/Resources/engine/node_modules
rm -rf Dross.app/Contents/Resources/engine/node_modules/typescript
cp -R "$ROOT/node_modules/typescript" Dross.app/Contents/Resources/engine/node_modules/
# So Node treats bundled .js as ESM even when the .app isn’t inside the repo.
printf '%s\n' '{"type":"module"}' > Dross.app/Contents/Resources/engine/package.json

# Nudge LaunchServices to pick up icon changes
touch Dross.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f Dross.app 2>/dev/null || true

open Dross.app
echo "Relaunched (engine → Contents/Resources/engine/)."
