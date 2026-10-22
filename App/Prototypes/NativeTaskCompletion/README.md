# Throwaway native completion options

Question: which simple native removal should replace the stuttering custom cover?

A: stock SwiftUI List removal with `withAnimation(.default)`.
B: native opacity fade (200 ms), then stock List removal.
C: native opacity fade (200 ms), then immediate gap closure.

All preserve SF Symbols Replace and a 400 ms tick settle plus one-second hold.
Rows use the production TaskListLabel in a native Today List, with five in-memory tasks. No saving, sync, custom mask, geometry observer, height interpolation, or persistence. Native capture proves the rendering in this harness, not performance in a real synced task list. No option is promoted until the user chooses.

Build the Debug simulator app. Launch with `SIMCTL_CHILD_TSK_NATIVE_COMPLETION_VARIANT=A SIMCTL_CHILD_TSK_NATIVE_COMPLETION_AUTOPLAY=1 xcrun simctl launch <udid> com.julesseguin.tsk` (choose A/B/C). The on-screen controls also replay and switch variants. Open index.html for the native recording comparison.

Visual report: `~/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T165654Z-native-options.html` (736,518 bytes). All 18 images, enlargement, six playback selections, URL variants and phone-width layout checked in Chrome. Both owned simulators were shut down. No production performance claim or verdict.

## Verdict

The user rejected all three native alternatives: “Not a fan. Let’s go back to the previous idea but debug the studderness”. Keep the previously selected soft top/bottom cover, then gap closure. Investigate the real production animation rather than promoting any alternative from this prototype.
