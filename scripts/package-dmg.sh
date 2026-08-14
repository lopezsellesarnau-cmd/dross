#!/usr/bin/env bash
# package-dmg.sh — build a distributable Dross.app + DMG.
#
# Usage:
#   ./scripts/package-dmg.sh              # unsigned local DMG (dev)
#   SIGN_IDENTITY="Developer ID Application: …" \
#   NOTARIZE_PROFILE="notarytool-profile" \
#     ./scripts/package-dmg.sh            # signed + notarized (release)
#
# Prerequisites for release:
#   - Xcode + Developer ID Application certificate in Keychain
#   - notarytool keychain profile (xcrun notarytool store-credentials …)
#   - Node 20+ for the engine build
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
DIST="$ROOT/dist-release"
APP_NAME="Dross"
VERSION="${VERSION:-0.1.0}"
DMG_NAME="Dross-${VERSION}"

echo "==> Building engine"
(cd "$ROOT" && npm run build)

echo "==> Building Swift (release)"
(cd "$APP_DIR" && swift build -c release)

BIN="$APP_DIR/.build/arm64-apple-macosx/release/DrossApp"
BUNDLE="$APP_DIR/.build/arm64-apple-macosx/release/DrossApp_DrossApp.bundle"
if [[ ! -x "$BIN" ]]; then
  # Fallback path when triple folder differs
  BIN="$(find "$APP_DIR/.build" -path '*/release/DrossApp' -type f | head -1)"
  BUNDLE="$(find "$APP_DIR/.build" -path '*/release/DrossApp_DrossApp.bundle' -type d | head -1)"
fi
[[ -x "$BIN" ]] || { echo "Release binary not found"; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST/${APP_NAME}.app/Contents/MacOS" "$DIST/${APP_NAME}.app/Contents/Resources/engine"

# Prefer existing Info.plist from debug .app if present
if [[ -f "$APP_DIR/Dross.app/Contents/Info.plist" ]]; then
  cp "$APP_DIR/Dross.app/Contents/Info.plist" "$DIST/${APP_NAME}.app/Contents/"
else
  cat > "$DIST/${APP_NAME}.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DrossApp</string>
  <key>CFBundleIdentifier</key><string>com.arnolop.dross</string>
  <key>CFBundleName</key><string>Dross</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi

cp "$BIN" "$DIST/${APP_NAME}.app/Contents/MacOS/DrossApp"
chmod +x "$DIST/${APP_NAME}.app/Contents/MacOS/DrossApp"
if [[ -d "$BUNDLE" ]]; then
  cp -R "$BUNDLE" "$DIST/${APP_NAME}.app/Contents/MacOS/"
fi
if [[ -f "$APP_DIR/AppIcon.icns" ]]; then
  cp "$APP_DIR/AppIcon.icns" "$DIST/${APP_NAME}.app/Contents/Resources/AppIcon.icns"
fi
cp -R "$ROOT/dist/"* "$DIST/${APP_NAME}.app/Contents/Resources/engine/"
# Engine parses with the TypeScript compiler API — bundle it so the shipped
# .app can `import 'typescript'` (must be in place before codesign below).
mkdir -p "$DIST/${APP_NAME}.app/Contents/Resources/engine/node_modules"
cp -R "$ROOT/node_modules/typescript" "$DIST/${APP_NAME}.app/Contents/Resources/engine/node_modules/"
printf '%s\n' '{"type":"module"}' > "$DIST/${APP_NAME}.app/Contents/Resources/engine/package.json"

APP="$DIST/${APP_NAME}.app"

# SPM resource bundle is Resources/icon only. codesign requires a real
# bundle layout (Contents/Info.plist). Bundle.module still resolves.
RES_BUNDLE="$APP/Contents/MacOS/DrossApp_DrossApp.bundle"
if [[ -d "$RES_BUNDLE" ]]; then
  mkdir -p "$RES_BUNDLE/Contents"
  if [[ -d "$RES_BUNDLE/Resources" && ! -d "$RES_BUNDLE/Contents/Resources" ]]; then
    mv "$RES_BUNDLE/Resources" "$RES_BUNDLE/Contents/Resources"
  fi
  cat > "$RES_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.arnolop.dross.resources</string>
  <key>CFBundleName</key>
  <string>DrossApp_DrossApp</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>MacOSX</string></array>
</dict>
</plist>
PLIST
  rm -f "$RES_BUNDLE/Info.plist"
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Codesign ($SIGN_IDENTITY)"
  SIGN=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
  if [[ -d "$RES_BUNDLE" ]]; then
    codesign "${SIGN[@]}" "$RES_BUNDLE"
  fi
  codesign "${SIGN[@]}" "$APP/Contents/MacOS/DrossApp"
  codesign "${SIGN[@]}" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "==> Skipping codesign (set SIGN_IDENTITY for release)"
fi

echo "==> Creating DMG"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/${DMG_NAME}.dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/${DMG_NAME}.dmg" || true
fi

if [[ -n "${NOTARIZE_PROFILE:-}" ]]; then
  echo "==> Notarize"
  xcrun notarytool submit "$DIST/${DMG_NAME}.dmg" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait
  xcrun stapler staple "$DIST/${DMG_NAME}.dmg"
  echo "==> Stapled"
else
  echo "==> Skipping notarize (set NOTARIZE_PROFILE for release)"
fi

echo ""
echo "Done: $DIST/${DMG_NAME}.dmg"
echo "CLI for CI:  npm run build && node dist/cli.js scan . --json"
