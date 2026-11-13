#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Run this staging helper from Terminal on your Mac.' >&2
    exit 1
fi
umask 077
if [[ ! -x .stage-reminders || stage-reminders.swift -nt .stage-reminders || usage.plist -nt .stage-reminders ]]; then
    xcrun swiftc -parse-as-library stage-reminders.swift -o .stage-reminders \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker usage.plist
    codesign --force --sign - --identifier com.julesseg.tsk.sorted-migration .stage-reminders
fi
exec ./.stage-reminders manifest.json "$@"
