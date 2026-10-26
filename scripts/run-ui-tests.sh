#!/usr/bin/env bash
set -euo pipefail
simulator_id=${1:?Pass the target simulator UDID followed by xcodebuild arguments}
shift
spotlight_capture_pid=""
spotlight_stop_file=""
booted_by_runner=false
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
            find "$container/Documents" -maxdepth 1 \( -name 'keyboard-fixture-*.json' -o -name 'participant-fixture-*.json' -o -name 'reminders-fixture-*.json' -o -name 'calendar-fixture-*.json' -o -name 'widgets-*.json' -o -name 'notifications-fixture-*.json' \) -exec cp {} "$TSK_EVENTKIT_EVIDENCE_DIR/" \;
        fi
        group=$(xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk group.com.julesseguin.tsk 2>/dev/null || true)
        if [[ -n "$group" && -d "$group/UITestDiagnostics" ]]; then
            find "$group/UITestDiagnostics" -maxdepth 1 -name 'participant-fixture-share-*.json' -exec cp {} "$TSK_EVENTKIT_EVIDENCE_DIR/" \;
        fi
        if [[ "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
            python3 "$(dirname "${BASH_SOURCE[0]}")/summarize-ui-boundaries.py" "$TSK_EVENTKIT_EVIDENCE_DIR" || true
        fi
    fi
    if [[ "$booted_by_runner" == true ]]; then
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
build_arguments=()
share_arguments=()
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
            share_arguments+=("$1" "$2")
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
            share_arguments+=("$1")
            shift ;;
    esac
done
if [[ -z "$derived_data" || -z "$result_path" ]]; then
    echo 'UI tests require explicit derivedDataPath and resultBundlePath for the installed share fixture.' >&2
    exit 1
fi
test_phases=$(python3 "$(dirname "${BASH_SOURCE[0]}")/ui-test-selection.py" phases -- ${test_filters[@]+"${test_filters[@]}"})
if [[ "$skip_build" == true ]]; then
    if [[ ! -d "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app" ]]; then
        echo 'Prebuilt UI tests require existing signed simulator products.' >&2
        exit 1
    fi
else
    xcodebuild build-for-testing -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}"
fi
execution_limits=(-test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600)
spotlight_status=0
if [[ "$test_phases" == *spotlight* ]]; then
    python3 "$(dirname "${BASH_SOURCE[0]}")/run-spotlight-ui-tests.py" --template "$simulator_id" -- \
        "${build_arguments[@]}" -resultBundlePath "$result_path" || spotlight_status=$?
    printf 'Fresh Spotlight UI status: %s\n' "$spotlight_status"
    case "$spotlight_status" in
        0) ;;
        *) exit "$spotlight_status" ;;
    esac
fi
if [[ "$test_phases" == spotlight ]]; then
    exit "$spotlight_status"
fi
if [[ "$was_booted" == no ]]; then
    booted_by_runner=true
    xcrun simctl boot "$simulator_id"
fi
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/Tsk.app"
xcrun simctl get_app_container "$simulator_id" com.julesseguin.tsk app > /dev/null
build_arguments+=(-skip-testing:TskUITests/SpotlightUITests)
share_status=0
if [[ "$test_phases" == *share* ]]; then
    xcrun simctl install "$simulator_id" "$derived_data/Build/Products/Debug-iphonesimulator/TskShareFixture.app"
    xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${share_arguments[@]}" -only-testing:TskUITests/ShareCaptureUITests -resultBundlePath "${result_path%.xcresult}-sharing.xcresult" || share_status=$?
fi
printf 'Share-first UI status: %s\n' "$share_status"
case "$share_status" in
    0|65) ;;
    130|143) exit "$share_status" ;;
    *) exit "$share_status" ;;
esac
if [[ "$test_phases" != *main* ]]; then
    if [[ "$spotlight_status" -ne 0 ]]; then exit "$spotlight_status"; fi
    exit "$share_status"
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
if [[ "${TSK_NATIVE_KEYBOARD_HID:-0}" == 1 && ( "${CI:-false}" != true || "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" != 1 || "$was_booted" != no || -z "${TSK_EVENTKIT_EVIDENCE_DIR:-}" ) ]]; then
    echo 'Native keyboard transport requires the CI-owned isolated simulator and evidence directory.' >&2
    exit 1
fi
if [[ -n "${TSK_EVENTKIT_EVIDENCE_DIR:-}" && "${CI:-false}" == true && "${TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR:-0}" == 1 && "$was_booted" == no ]]; then
    if [[ "${TSK_NATIVE_KEYBOARD_HID:-0}" == 1 ]]; then
        python3 "$(dirname "${BASH_SOURCE[0]}")/relay-ui-test-boundaries.py" --device "$simulator_id" --evidence "$TSK_EVENTKIT_EVIDENCE_DIR" --owned-simulator --owned-cleanup-grace-seconds 120 -- \
            python3 "$(dirname "${BASH_SOURCE[0]}")/with-native-keyboard-hid.py" --udid "$simulator_id" \
            --tool-root "${TSK_NATIVE_KEYBOARD_HID_TOOL_ROOT:?Pass the pinned .build HID tools}" \
            --evidence "$TSK_EVENTKIT_EVIDENCE_DIR/native-keyboard-hid" -- \
            xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -skip-testing:TskUITests/ShareCaptureUITests -resultBundlePath "$result_path" || main_status=$?
    else
    python3 "$(dirname "${BASH_SOURCE[0]}")/relay-ui-test-boundaries.py" --device "$simulator_id" --evidence "$TSK_EVENTKIT_EVIDENCE_DIR" --owned-simulator -- xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -skip-testing:TskUITests/ShareCaptureUITests -resultBundlePath "$result_path" || main_status=$?
    fi
else
    xcodebuild test-without-building "${execution_limits[@]}" -collect-test-diagnostics never -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO "${build_arguments[@]}" -skip-testing:TskUITests/ShareCaptureUITests -resultBundlePath "$result_path" || main_status=$?
fi
stop_spotlight_capture
printf 'Remaining UI status: %s\n' "$main_status"
case "$main_status" in
    0|65) ;;
    130|143) exit "$main_status" ;;
    *) exit "$main_status" ;;
esac
if [[ "$share_status" -ne 0 ]]; then
    exit "$share_status"
fi
if [[ "$spotlight_status" -ne 0 ]]; then
    exit "$spotlight_status"
fi
exit "$main_status"
