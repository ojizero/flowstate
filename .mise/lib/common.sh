#!/bin/bash
# Shared by file tasks; this directory is deliberately outside task discovery.
set -euo pipefail
FLOWSTATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$FLOWSTATE_ROOT"
FLOWSTATE_APP="$FLOWSTATE_ROOT/build/Flow State.app"

require_xcode() {
    if [[ "$(uname -s)" != Darwin || ! -x "${DEVELOPER_DIR:-}/usr/bin/xcodebuild" ]]; then
        echo "Full Xcode is required. Set DEVELOPER_DIR in mise.local.toml to its Contents/Developer directory." >&2
        return 1
    fi
    local xcode_version swift_version
    xcode_version="$(/usr/bin/xcodebuild -version | /usr/bin/awk '/^Xcode / { print $2 }')"
    swift_version="$(/usr/bin/xcrun --toolchain XcodeDefault swift --version 2>/dev/null | /usr/bin/sed -n 's/.*Apple Swift version \([^ ]*\).*/\1/p')"
    if [[ "$xcode_version" != "$FLOWSTATE_XCODE_VERSION" || "$swift_version" != "$FLOWSTATE_SWIFT_VERSION" ]]; then
        printf 'Expected Xcode %s / Apple Swift %s; found Xcode %s / Swift %s.\n' \
            "$FLOWSTATE_XCODE_VERSION" "$FLOWSTATE_SWIFT_VERSION" "$xcode_version" "$swift_version" >&2
        echo "Select the matching Xcode installation, or override the version pins together in mise.local.toml." >&2
        return 1
    fi
}

require_toolchain() {
    require_xcode
    local actual expected
    actual="$(command -v swift)"
    expected="$(/usr/bin/xcrun --toolchain XcodeDefault --find swift)"
    if [[ ! "$actual" -ef "$expected" ]]; then
        echo "Swift is not the selected Xcode toolchain. Run mise run setup, then use mise run or mise exec." >&2
        return 1
    fi
}
