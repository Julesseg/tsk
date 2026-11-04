#!/usr/bin/env bash
set -euo pipefail

if [ "${AGENT_REMOTE:-false}" = "true" ]; then
  cat <<'EOF'
ENV=REMOTE LINUX. No iOS simulator/runtime exists here, so the App/ Xcode
target and the TskUITests XCUITest suite cannot run on this machine. Exercise
the portable logic with `cd Core && swift test`, implement UI work normally,
and let the `App · XCUITest (macOS)` CI job verify UI behavior.
EOF
elif [ "$(uname -s)" = "Linux" ]; then
  cat <<'EOF'
ENV=LOCAL LINUX. No Xcode or iOS simulator exists here, so the App/ target and
the TskUITests XCUITest suite cannot run on this machine. Implement UI work
normally and let CI verify it.
EOF
  if command -v swift >/dev/null 2>&1 || [ -x "$HOME/.local/share/swiftly/bin/swift" ]; then
    printf '%s\n' 'A Swift toolchain is available. Run the portable tests with `cd Core && swift test`.'
  else
    printf '%s\n' 'No Swift toolchain was found. Report that local Core tests could not run; CI still runs them.'
  fi
else
  cat <<'EOF'
ENV=LOCAL MAC. Xcode is available, so UI tests can run locally when useful.
`cd Core && swift test` remains the fast loop. PR CI runs UI smoke coverage;
nightly/manual CI runs full UI coverage (docs/verification/ci-test-tiers.md).
In T3 Code, use its device tools for interactive checks (docs/agents/t3-code.md).
For automated UI tests, use scripts/run-ui-tests.sh with the target UDID and
explicit derivedDataPath and resultBundlePath. Build the native simulator
bridge first. Preserve already-booted simulators and shut down only devices
this task booted when verification finishes.
EOF
fi
