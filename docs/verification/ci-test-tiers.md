# CI test tiers

Pull requests and pushes to `main` with non-documentation changes run all Core
and persistent Native tests, plus a small UI smoke selection on both device
families. The existing `App · XCUITest (macOS)` and `App · XCUITest (iPad)`
check names remain the branch-protection gates.

| UI coverage | iPhone | iPad | Trigger |
| --- | --- | --- | --- |
| Smoke | 8 methods | 6 methods | PR, push, manual `ui_suite=smoke` |
| Full | All 75 declared methods | 66-method selection | Nightly at 02:00 UTC, manual `ui_suite=full` |
| Diagnostic | 12-method subset | — | Manual `diagnostic_only=true` |
| Keyboard diagnostics | 11-method subset | 9-method subset | Manual `ui_suite=keyboard` |
| Text diagnostics | 5-method subset | 5-method subset | Manual `ui_suite=text` |

The iPhone smoke journeys cover capture/validation/cancel/reopen; row title and
attribute editing, picker dismissal, invalid-draft retention and durable
completion; persisted view ordering and capacity; and real-server synchronization.
The iPad journeys cover the same row round trip and adaptive landscape/portrait
project/date views. Both families also exercise continuous swipe selection,
held-touch row/scroll stability during a data refresh, atomic completion,
Upcoming duplicates, failure retention, view changes and editor validation.

Physical-keyboard journeys run in full/nightly and focused keyboard/text
diagnostics. PR smoke does not certify physical-keyboard delivery. This keeps
ordinary task editing independent of the native keyboard companion's startup.
Full and diagnostic selections still require the owned transport whenever they
include a hardware-keyboard case; a missing transport fails before XCTest can
silently use the local fallback. Native request proofs, assertions and deadlines
are unchanged. The workflow installs the companion only for those selections.

Installed Share capture, widgets, all three Spotlight scenarios, Settings tours,
appearance/accessibility permutations, annotations, recurrence, Reminders,
Calendar, notifications, exhaustive typed attributes and filters, and additional
persistence/error journeys run in full coverage. Moving a scenario to full
coverage does not establish that it passed. System changes still require actual
native full-suite results before acceptance. See [the consolidation audit](test-suite-consolidation.md)
for the merged methods and measured baseline.

Smoke uses one worker per family. Full coverage uses disjoint workspace and
row-editing workers: 68 + 7 methods on iPhone and 59 + 7 on iPad. Each method is
selected once per family. Native HID cases remain in the workspace worker with
their existing identity checks and deadlines. The row-only worker selects no
native command cases and uses XCTest input. Focused diagnostic dispatches use
one worker per selected family. Each worker builds once, owns one disposable
simulator, and runs Share before the remaining cases when selected.

The gates inspect jobs from the current run attempt and require every expected
worker for their family to complete successfully. Missing, duplicate, skipped,
cancelled, failed or pending workers fail the gate. Existing workspace artifact
names remain; full row artifacts add `-row-editing`.

Portable selection, routing, installer, relay, owner and cleanup regressions run
once in the Linux routing job. Calendar controller regressions run once in the
iPhone workspace/all Mac worker. Native runtime and input acceptance remain in
the actual iPhone/iPad workers. An independent peer verifies the uploaded task
whenever the real-server synchronization journey is selected.

Documentation-only changes skip Core/Native builds and run the named UI workers
on Linux without Xcode or simulators. Routing inspects the complete PR diff from
its merge base, or the before/after range for a push. Its allowlist is root
Markdown and license files, nested `README.md` files, and documentation/text/image/PDF
files under `docs/`. Unknown paths, mixed changes, executable examples, empty
diffs, missing commits and classification errors run normal tests. Renames
inspect both paths. Nightly and manual dispatches always run tests. The Release
workflow also excludes documentation-only changes.

UI products build in a separate 20-minute step before simulator creation.
Execution reuses those signed arm64 products with `--skip-build`. Xcode 27.0
is explicit. The simulator selector matches the selected SDK's major/minor
release, preserving the runtime repair on `main`; a newer installed runtime
cannot silently change the lane. Its portable selection checks run in routing.
Smoke keeps its 45-minute execution and 60-minute worker limits. Full keeps
150/180-minute execution/worker limits; diagnostics keep 60/90. Every method
keeps its 600-second XCTest limit. These are ceilings, not measured durations.
The `always()` cleanup removes the owned simulator after failure or timeout.

Full and diagnostic native keyboard admission retains UP-only initialization, a live owned relay
and companion, fixed case/phase sequences, nonce/PID/device/socket checks,
30-second initialization and 10-second arming limits. Requests retain their
12-second deadline and five-second dispatch reservation. Container prefetch
retains its 30-second cap, exact owner/attempt/nonce validation and child cleanup.
There is no command replay or automatic test retry. Keyboard-dismissal controls
still require visible keyboard geometry and two stable samples inside the
20-second control deadline. Native menu selection checks the exact ordered menu
and two stable, finite, ancestor-contained row snapshots, then performs one tap
at that admitted position without resolving the disappearing menu button again.

Run full coverage on both families before accepting system integrations,
workflow changes, or behavior outside smoke coverage:

```sh
gh workflow run ci.yml --repo Julesseg/tsk --ref <branch> -f ui_suite=full
```

Manual dispatch defaults to full. Manual, scheduled and PR/push runs have
separate concurrency groups; repeated dispatches on one branch replace each
other. Verify the actual run head SHA. Keyboard/text diagnostics have separate
names and concurrency groups and cannot satisfy canonical branch protection.
Appearance captures require visual confirmation; source, builds and focused
checks do not establish system delivery or signed-distribution acceptance.

Inspect selections without booting a simulator:

```sh
python3 scripts/ui-test-selection.py select smoke iPhone
python3 scripts/ui-test-selection.py select full iPad --partition workspace
python3 scripts/test-ui-test-selection.py
```
