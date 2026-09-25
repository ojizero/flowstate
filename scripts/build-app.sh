#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Compatibility entry point. Mise owns the toolchain and lifecycle tasks.
mise run bundle
if [[ "${1:-}" == "--open" ]]; then mise run start; fi
