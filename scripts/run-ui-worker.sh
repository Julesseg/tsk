#!/usr/bin/env bash
set -euo pipefail
simulator_id="$1"
coverage=()
selection=$(python3 ../scripts/ui-test-selection.py select "$UI_SUITE" "$UI_FAMILY" --partition "$UI_PARTITION")
while IFS= read -r selector; do
    if [[ -n "$selector" ]]; then coverage+=("$selector"); fi
done <<< "$selection"
printf 'UI suite: %s (%s, %s)\n%s\n' "$UI_SUITE" "$UI_FAMILY" "$UI_PARTITION" "$selection"
export TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR=1
export TSK_EVENTKIT_EVIDENCE_DIR="$PWD/../.build/eventkit-fixture"
export TSK_NATIVE_KEYBOARD_HID_TOOL_ROOT="$PWD/../.build/native-keyboard-hid"
export TSK_TASKCHAMPION_LIBRARY="$PWD/../.build/ui-tools/libtsk_taskchampion.dylib"
export TSK_NATIVE_KEYBOARD_HID=0
if [[ $(python3 ../scripts/ui-test-selection.py native-keyboard -- "${coverage[@]}") == yes ]]; then
    export TSK_NATIVE_KEYBOARD_HID=1
fi
command=(/bin/bash ../scripts/run-ui-tests.sh "$simulator_id" --skip-build
    -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" "${coverage[@]}"
    -resultBundlePath TestResults.xcresult -derivedDataPath ../.build/ui
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
if [[ $(python3 ../scripts/ui-test-selection.py sync-server -- "${coverage[@]}") == yes ]]; then
    peer=()
    if [[ $(python3 ../scripts/ui-test-selection.py sync-peer -- "${coverage[@]}") == yes ]]; then
        peer=(--verify-peer ../.build/ui-tools/tsk-native-probe)
    fi
    exec python3 ../scripts/with-sync-fixture.py --server ../.build/ui-tools/taskchampion-sync-server --output ../.build/ui-sync "${peer[@]}" -- "${command[@]}"
fi
exec "${command[@]}"
