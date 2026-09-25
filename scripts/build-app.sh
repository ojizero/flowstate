#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Full Xcode supplies SwiftUI compiler plugins missing from some CLT installations.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --product Flowstate
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/build/Flowstate.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/Flowstate" "$APP_DIR/Contents/MacOS/Flowstate"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
if [[ "${1:-}" == "--open" ]]; then open "$APP_DIR"; fi
