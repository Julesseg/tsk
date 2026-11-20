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
export TEST_RUNNER_TSK_UI_DIAGNOSTICS=0
case "$UI_SUITE" in
    diagnostic|text|regression|menu) export TEST_RUNNER_TSK_UI_DIAGNOSTICS=1 ;;
esac
export TSK_EVENTKIT_EVIDENCE_DIR="$PWD/../.build/eventkit-fixture"
export TSK_TASKCHAMPION_LIBRARY="$PWD/../.build/ui-tools/libtsk_taskchampion.dylib"
command=(/bin/bash ../scripts/run-ui-tests.sh "$simulator_id" --skip-build
    -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" "${coverage[@]}"
    -resultBundlePath TestResults.xcresult -derivedDataPath ../.build/ui
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
if [[ $(python3 ../scripts/ui-test-selection.py sync-server -- "${coverage[@]}") == yes ]]; then
    fixture=(--server ../.build/ui-tools/taskchampion-sync-server --output ../.build/ui-sync)
    if [[ $(python3 ../scripts/ui-test-selection.py sync-peer -- "${coverage[@]}") == yes ]]; then
        fixture+=(--verify-peer ../.build/ui-tools/tsk-native-probe)
    fi
    if [[ "$UI_SUITE" == sync ]]; then fixture+=(--trace-loopback); fi
    exec python3 ../scripts/with-sync-fixture.py "${fixture[@]}" -- "${command[@]}"
fi
exec "${command[@]}"
