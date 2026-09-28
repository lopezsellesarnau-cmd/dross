#!/bin/bash
# Copy the engine's runtime dependencies into a bundled engine folder.
# Usage: scripts/copy-engine-deps.sh <engine-dir>
#
# The engine runs from Contents/Resources/engine/ inside the .app, outside
# this checkout, so every package it imports at runtime must ship with it:
# the production dependency tree (@anthropic-ai/sdk and its deps) plus
# `typescript`, which contract-drift imports for the AST parser.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$1/node_modules"
[ -n "$1" ] || { echo "usage: $0 <engine-dir>" >&2; exit 2; }

rm -rf "$DEST"
mkdir -p "$DEST"
cd "$ROOT"
# `npm ls --parseable` lists absolute package paths, the root first.
npm ls --omit=dev --all --parseable | tail -n +2 | while read -r dep; do
  rel="${dep#*/node_modules/}"          # keeps nested node_modules/… paths
  mkdir -p "$DEST/$(dirname "$rel")"
  cp -R "$dep" "$DEST/$rel"
done
cp -R "$ROOT/node_modules/typescript" "$DEST/"
