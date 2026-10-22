# Task completion motion prototype

Three ways to cover stationary task content from above and below, switchable via `?variant=A`, `B`, or `C` and a floating switcher on the same Today surface.

Open `index.html` in a browser. State lives in memory; Replay restores the sample list. Slow motion and light/dark controls are part of the experiment.

- A: cover fully, then close the gap.
- B: cover while the following rows start moving up.
- C: soft cover edges, then close the gap.

The browser checkmark is illustrative. Production uses SF Symbols Replace, verified separately in canonical iPhone/iPad XCUITest recordings. The user selected C: soft cover, then close gap. The native implementation is being added to PR #59.

## Decision

On 2026-10-22 the user selected: “C — soft cover, then close gap”. This settles the motion question: cover stationary task content from above and below with soft edges, then close the empty gap. Keep the task content unscaled and unmoved while it is visible.

Variant C uses a 420 ms cover followed by a 240 ms empty-gap closure. The production implementation is SwiftUI rather than embedded browser code. Native SF Symbols tick animation and the checked hold are preserved independently.
