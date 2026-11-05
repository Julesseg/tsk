#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
source_dir="$repo_root/.build/taskwarrior"
archive="$repo_root/.build/taskwarrior-3.5.0.tar.gz"
mkdir -p "$source_dir"
if [[ -e "$source_dir/.git" ]]; then
    echo 'The Taskwarrior release fixture cannot use a Git checkout.' >&2
    exit 1
fi
curl -fsSL https://github.com/GothenburgBitFactory/taskwarrior/releases/download/v3.5.0/task-3.5.0.tar.gz -o "$archive"
python3 - "$archive" <<'PY'
import hashlib
import pathlib
import sys

expected = '9ea64b411f8314414f440ec765dfdf5a86c9f6159df47e2f60cff3db6b31157a'
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != expected:
    raise SystemExit('Taskwarrior 3.5.0 release checksum mismatch')
PY
tar -xzf "$archive" --strip-components=1 -C "$source_dir"
cmake -S "$source_dir" -B "$source_dir/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$repo_root/.build/taskwarrior-install"
cmake --build "$source_dir/build" --target task_executable --parallel 2
cmake --install "$source_dir/build"
