#!/usr/bin/env bash
set -euo pipefail
simulator_id=${1:?Pass the target simulator UDID followed by xcodebuild arguments}
shift
booted_file=$(mktemp)
xcrun simctl list devices booted --json > "$booted_file"
was_booted=$(python3 - "$booted_file" "$simulator_id" <<'PY'
import json, sys
from pathlib import Path
initial = json.loads(Path(sys.argv[1]).read_text())['devices']
print('yes' if any(device['udid'] == sys.argv[2] and device['state'] == 'Booted' for devices in initial.values() for device in devices) else 'no')
PY
)
cleanup() {
    if [[ -n "${TSK_EVENTKIT_EVIDENCE_DIR:-}" ]]; then
        mkdir -p "$TSK_EVENTKIT_EVIDENCE_DIR"
        container=$(xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk data 2>/dev/null || true)
        if [[ -n "$container" && -d "$container/Documents" ]]; then
            find "$container/Documents" -maxdepth 1 -name 'reminders-fixture-*.json' -exec cp {} "$TSK_EVENTKIT_EVIDENCE_DIR/" \;
        fi
    fi
    if [[ "$was_booted" == no ]]; then
        xcrun simctl shutdown "$simulator_id" || true
    fi
    python3 - "$booted_file" <<'PY'
import json, subprocess, sys
from pathlib import Path
state = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
if not any(device['state'] == 'Booted' for devices in state['devices'].values() for device in devices):
    subprocess.run(['osascript', '-e', 'quit app "Simulator"'], check=False)
Path(sys.argv[1]).unlink(missing_ok=True)
PY
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$was_booted" == no ]]; then
    xcrun simctl boot "$simulator_id"
fi
xcrun simctl bootstatus "$simulator_id" -b
xcodebuild test -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "$@"
