#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Run this importer on your Mac.' >&2
    exit 1
fi
umask 077
exec /usr/bin/python3 import-direct.py "$@"
