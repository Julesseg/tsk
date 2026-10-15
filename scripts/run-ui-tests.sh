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
            find "$container/Documents" -maxdepth 1 \( -name 'keyboard-fixture-*.json' -o -name 'participant-fixture-*.json' -o -name 'reminders-fixture-*.json' -o -name 'calendar-fixture-*.json' -o -name 'widgets-*.json' -o -name 'notifications-fixture-*.json' \) -exec cp {} "$TSK_EVENTKIT_EVIDENCE_DIR/" \;
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
build_arguments=()
share_arguments=()
derived_data=""
result_path=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -derivedDataPath)
            derived_data=$2
            build_arguments+=("$1" "$2")
            share_arguments+=("$1" "$2")
            shift 2 ;;
        -resultBundlePath)
            result_path=$2
            shift 2 ;;
        -only-testing:*|-skip-testing:*)
            build_arguments+=("$1")
            shift ;;
        *)
            build_arguments+=("$1")
            share_arguments+=("$1")
            shift ;;
    esac
done
if [[ -z "$derived_data" || -z "$result_path" ]]; then
    echo 'UI tests require explicit derivedDataPath and resultBundlePath for the installed share fixture.' >&2
    exit 1
fi
xcodebuild build-for-testing -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}"
xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app"
xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk app > /dev/null
xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/TskShareFixture.app"
share_status=0
xcodebuild test-without-building -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${share_arguments[@]}" -only-testing:TskUITests/ShareCaptureUITests -resultBundlePath "${result_path%.xcresult}-sharing.xcresult" || share_status=$?
printf 'Share-first UI status: %s\n' "$share_status"
case "$share_status" in
    0|65) ;;
    130|143) exit "$share_status" ;;
    *) exit "$share_status" ;;
esac
main_status=0
xcodebuild test-without-building -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -skip-testing:TskUITests/ShareCaptureUITests -resultBundlePath "$result_path" || main_status=$?
printf 'Remaining UI status: %s\n' "$main_status"
case "$main_status" in
    0|65) ;;
    130|143) exit "$main_status" ;;
    *) exit "$main_status" ;;
esac
if [[ "$share_status" -ne 0 ]]; then
    exit "$share_status"
fi
exit "$main_status"
