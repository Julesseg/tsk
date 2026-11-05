#!/usr/bin/env bash
set -euo pipefail
unset ELECTRON_RUN_AS_NODE
exec python3 "$(dirname "$0")/remote-ios.py" "$@"
