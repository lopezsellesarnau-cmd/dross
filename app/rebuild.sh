#!/bin/bash
# Rebuilds DrossApp and repackages it into the .app bundle — the SPM
# executable + its resource bundle both need copying in, not just the
# binary, or Bundle.module lookups (the logo, drawer art) fail silently at
# runtime with no build error to catch it.
set -e
cd "$(dirname "$0")"

osascript -e 'quit app "Dross"' 2>/dev/null || true
pkill -f DrossApp 2>/dev/null || true
sleep 1

swift build

cp .build/arm64-apple-macosx/debug/DrossApp Dross.app/Contents/MacOS/DrossApp
rm -rf Dross.app/Contents/MacOS/DrossApp_DrossApp.bundle
cp -r .build/arm64-apple-macosx/debug/DrossApp_DrossApp.bundle Dross.app/Contents/MacOS/

open Dross.app
echo "Relaunched."
