#!/bin/sh
set -eu
udid=${1:?Pass an already booted simulator UDID}
variant=${2:-A}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
derived=/tmp/tsk-native-completion-derived
cd "$root"
xcodebuild build -project App/Tsk.xcodeproj -scheme Tsk -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/Tsk.app"
SIMCTL_CHILD_TSK_NATIVE_COMPLETION_VARIANT="$variant" xcrun simctl launch --terminate-running-process "$udid" com.julesseguin.tsk
