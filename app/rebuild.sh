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

# rm first: cp over the existing binary keeps the same inode, and macOS
# caches code signatures per vnode — the new bytes then fail the cached
# signature and the kernel SIGKILLs the app at launch ("Code Signature
# Invalid"). A fresh file keeps the linker's own ad-hoc signature valid.
rm -f Dross.app/Contents/MacOS/DrossApp
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
# Runtime deps (typescript for the AST, @anthropic-ai/sdk for the LLM pass).
"$ROOT/scripts/copy-engine-deps.sh" Dross.app/Contents/Resources/engine
# So Node treats bundled .js as ESM even when the .app isn’t inside the repo.
printf '%s\n' '{"type":"module"}' > Dross.app/Contents/Resources/engine/package.json

# Nudge LaunchServices to pick up icon changes
touch Dross.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f Dross.app 2>/dev/null || true

open Dross.app
echo "Relaunched (engine → Contents/Resources/engine/)."
