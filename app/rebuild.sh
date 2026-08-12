#!/bin/bash
# Rebuilds ShipCheckApp and repackages it into the .app bundle — the SPM
# executable + its resource bundle both need copying in, not just the
# binary, or Bundle.module lookups (the logo, drawer art) fail silently at
# runtime with no build error to catch it.
set -e
cd "$(dirname "$0")"

osascript -e 'quit app "ShipCheck"' 2>/dev/null || true
pkill -f ShipCheckApp 2>/dev/null || true
sleep 1

swift build

cp .build/arm64-apple-macosx/debug/ShipCheckApp ShipCheckApp.app/Contents/MacOS/ShipCheckApp
rm -rf ShipCheckApp.app/Contents/MacOS/ShipCheckApp_ShipCheckApp.bundle
cp -r .build/arm64-apple-macosx/debug/ShipCheckApp_ShipCheckApp.bundle ShipCheckApp.app/Contents/MacOS/

open ShipCheckApp.app
echo "Relaunched."
