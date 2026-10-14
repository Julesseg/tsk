#!/usr/bin/env bash
set -euo pipefail
booted_file=$(mktemp)
xcrun simctl list devices booted --json > "$booted_file"
cleanup() {
    python3 - "$booted_file" <<'PY'
import json, subprocess, sys
from pathlib import Path
initial = {device['udid'] for devices in json.loads(Path(sys.argv[1]).read_text())['devices'].values() for device in devices if device['state'] == 'Booted'}
def booted():
    state = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    return {device['udid'] for devices in state['devices'].values() for device in devices if device['state'] == 'Booted'}
for udid in booted() - initial:
    subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False)
if not booted():
    subprocess.run(['osascript', '-e', 'quit app "Simulator"'], check=False)
Path(sys.argv[1]).unlink(missing_ok=True)
PY
}
trap cleanup EXIT
xcodebuild test "$@"
