#!/usr/bin/env bash
set -euo pipefail
lease_helper="$HOME/.config/bin/simulator-lease"
if [[ -x "$lease_helper" ]]; then
    if [[ -n "${SIMULATOR_LEASE_TOKEN:-}" && "${SIMULATOR_LEASE_MANAGED:-}" == 1 ]]; then
        "$lease_helper" check --token "$SIMULATOR_LEASE_TOKEN" --device "${1:?Pass the target simulator UDID}" > /dev/null
    else
        exec "$lease_helper" run --owner "tsk UI tests: $PWD" --device "${1:?Pass the target simulator UDID}" --wait 3600 -- /bin/bash "$0" "$@"
    fi
fi
simulator_id=${1:?Pass the target simulator UDID followed by xcodebuild arguments}
shift
spotlight_capture_pid=""
spotlight_stop_file=""
stop_spotlight_capture() {
    if [[ -n "$spotlight_capture_pid" ]]; then
        touch "$spotlight_stop_file"
        wait "$spotlight_capture_pid" || true
        spotlight_capture_pid=""
    fi
}
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
    stop_spotlight_capture
    if [[ -n "${TSK_EVENTKIT_EVIDENCE_DIR:-}" ]]; then
        mkdir -p "$TSK_EVENTKIT_EVIDENCE_DIR"
        if [[ "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
            python3 "$(dirname "${BASH_SOURCE[0]}")/capture-simulator-search-context.py" "$simulator_id" "$TSK_EVENTKIT_EVIDENCE_DIR/search-owned-simulator-context.json" || true
        fi
        container=$(xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk data 2>/dev/null || true)
        if [[ -n "$container" && -d "$container/Documents" ]]; then
            find "$container/Documents" -maxdepth 1 \( -name 'participant-fixture-*.json' -o -name 'reminders-fixture-*.json' -o -name 'calendar-fixture-*.json' -o -name 'notifications-fixture-*.json' \) -exec cp {} "$TSK_EVENTKIT_EVIDENCE_DIR/" \;
        fi
        if [[ "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
            python3 "$(dirname "${BASH_SOURCE[0]}")/summarize-ui-boundaries.py" "$TSK_EVENTKIT_EVIDENCE_DIR" || true
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
test_filters=()
skip_build=false
derived_data=""
result_path=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            skip_build=true
            shift ;;
        -derivedDataPath)
            derived_data=$2
            build_arguments+=("$1" "$2")
            shift 2 ;;
        -resultBundlePath)
            result_path=$2
            shift 2 ;;
        -only-testing:*|-skip-testing:*)
            build_arguments+=("$1")
            test_filters+=("$1")
            shift ;;
        *)
            build_arguments+=("$1")
            shift ;;
    esac
done
if [[ -z "$derived_data" || -z "$result_path" ]]; then
    echo 'UI tests require explicit derivedDataPath and resultBundlePath for the installed action fixture.' >&2
    exit 1
fi
action_fixture=$(python3 "$(dirname "${BASH_SOURCE[0]}")/ui-test-selection.py" action-fixture -- ${test_filters[@]+"${test_filters[@]}"})
if [[ "$skip_build" == true ]]; then
    if [[ ! -d "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app" ]]; then
        echo 'Prebuilt UI tests require existing signed simulator products.' >&2
        exit 1
    fi
else
    xcodebuild build-for-testing -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}"
fi
xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app"
xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk app > /dev/null
execution_limits=(-test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600)
if [[ "$action_fixture" == yes ]]; then
    xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/TskActionFixture.app"
fi
if [[ -n "${TSK_EVENTKIT_EVIDENCE_DIR:-}" && "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
    mkdir -p "$TSK_EVENTKIT_EVIDENCE_DIR"
    spotlight_stop_file="$TSK_EVENTKIT_EVIDENCE_DIR/spotlight-log-stop-$simulator_id"
    python3 -c 'from pathlib import Path; import sys; Path(sys.argv[1]).unlink(missing_ok=True)' "$spotlight_stop_file"
    codesign -dv --verbose=4 "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app" > "$TSK_EVENTKIT_EVIDENCE_DIR/spotlight-app-signature.txt" 2>&1 || true
    codesign -d --entitlements - "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app" > "$TSK_EVENTKIT_EVIDENCE_DIR/spotlight-app-entitlements.plist" 2> "$TSK_EVENTKIT_EVIDENCE_DIR/spotlight-app-entitlements-stderr.txt" || true
    python3 "$(dirname "${BASH_SOURCE[0]}")/capture-simulator-spotlight-log.py" "$simulator_id" "$TSK_EVENTKIT_EVIDENCE_DIR/spotlight-service.log" "$spotlight_stop_file" &
    spotlight_capture_pid=$!
fi
main_status=0
if [[ -n "${TSK_EVENTKIT_EVIDENCE_DIR:-}" && "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
    python3 "$(dirname "${BASH_SOURCE[0]}")/relay-ui-test-boundaries.py" --device "$simulator_id" --evidence "$TSK_EVENTKIT_EVIDENCE_DIR" --owned-simulator --monitor-device -- xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -resultBundlePath "$result_path" || main_status=$?
else
    xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -resultBundlePath "$result_path" || main_status=$?
fi
stop_spotlight_capture
printf 'Remaining UI status: %s\n' "$main_status"
case "$main_status" in
    0|65) ;;
    130|143) exit "$main_status" ;;
    *) exit "$main_status" ;;
esac
exit "$main_status"
