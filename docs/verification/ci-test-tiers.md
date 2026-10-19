# CI test tiers

Pull requests and pushes to `main` run all Core and persistent Native tests,
plus focused UI smoke coverage on both device families. Existing check names
stay unchanged for branch protection. The UI runner builds once per lane and
reuses that build, simulator and synchronization fixture. An independent peer
verifies the uploaded UI task whenever the real-server synchronization scenario
is selected. The iPad smoke selection exercises workspace/keyboard behavior and
does not create that server task.

| UI coverage | iPhone | iPad | Trigger |
| --- | --- | --- | --- |
| Smoke | 13 methods | 10 methods | PR, push, manual `ui_suite=smoke` |
| Full | All 55 declared methods | 45-method selection | Nightly at 02:00 UTC, manual `ui_suite=full` |
| Diagnostic | Existing 13-method subset | — | Manual `diagnostic_only=true` |
| Keyboard diagnostics | 11-method subset | 9-method subset | Manual `ui_suite=keyboard` |

Both device families check workspace control placement, every Settings destination,
Settings at the largest accessibility text size, persisted tab ordering and capacity,
and Projects drill-down. Both also hold an actual HTTP synchronization request open
to check title-adjacent progress and the absence of workspace synchronization footers,
then return a server failure and check that its details remain in Settings.
Appearance captures require visual confirmation of the
rendered mode. The iPhone smoke selection
checks capture/validation/cancel/reopen, durable
editing/completion, real-server synchronization, annotation toolbar saves,
native keyboard input, installed Share capture, installed widget behavior and
actual Spotlight opening/completion. The iPad selection checks keyboard-driven
capture/edit/completion/reopen, adaptive landscape/portrait views, custom views
at accessibility text sizes, modal annotation commands and native text input.
Share runs first only when selected; the iPad smoke lane skips its separate
launch and host-fixture installation.

Native task actions, exhaustive typed attributes and filters, recurrence, Reminders copy/move and
permission changes, notification delivery/revocation, stale/peer Spotlight
results and repeated persistence/error journeys remain in the full suite.
Existing workflows enter their destinations through Settings. iPad-only methods still
skip on iPhone. Source selectors live in `scripts/ui-test-selection.py`; its
checks reject renamed selectors and empty UI selections.

Keyboard diagnostics retain native command delivery, installed Share capture,
Calendar failure capture, workspace creation, view ordering and automatic-sync
failure recovery. They also exercise annotation creation, real-server connection
entry and typed rating menus on both families, plus dependency navigation and
project text replacement on iPhone. This focused manual selection uses the smoke time limits and
does not change PR or nightly coverage. Keyboard-dismissal admission requires a
visible software keyboard, a control outside its occupied area, and two stable
geometry samples within the existing 20-second control deadline.
Its distinct check names prevent the focused subset from satisfying the
canonical XCUITest branch-protection checks.
Its separate concurrency group allows diagnostics to run alongside full coverage;
repeated keyboard dispatches replace only the earlier keyboard run.

Native keyboard cases prepare the runner container in the background at case
start, with a 30-second discovery cap. Each request still keeps its original
12-second deadline and five-second dispatch reservation. A discovered path is
only cached for its device, runner bundle and process after checking the exact
owner, attempt and nonce request file; every subsequent request is checked too.
Outstanding discovery children are cancelled, reaped and recorded on exit.

UI products build in a separate 20-minute step before creating/booting a test
simulator. Execution reuses those signed arm64 products with `--skip-build`.
Smoke execution has a 45-minute step limit and a 60-minute overall job limit.
The expanded workspace selection exceeded the former 30-minute step limit;
the measured iPad run spent 10 minutes 33 seconds in simulator preparation
before starting `xcodebuild`. The additional budget covers preparation and
the selected journeys without changing individual test limits or assertions.
Full execution/job limits are 150/180 minutes; diagnostics have 60/90-minute limits.
These are ceilings, not measured completion times. Every method retains the
600-second XCTest limit. The later `always()` step removes the owned simulator
after a UI step failure or timeout. Runtime and signed-distribution acceptance
still require their actual results; a smoke pass establishes only its selected
workflows.

Run the full suite on a published branch before accepting changes to system
integrations or workflows outside smoke coverage:

```sh
gh workflow run ci.yml --repo Julesseg/tsk --ref <branch> -f ui_suite=full
```

Manual dispatch defaults to full coverage. The nightly schedule runs the
default branch once the workflow is merged. Manual, scheduled and PR/push
runs have separate concurrency groups, so dispatching full coverage preserves
an active PR run. Repeated dispatches on the same branch replace each other.
Verify the run's head SHA before attributing its result to a change. Existing
artifact names and ownership/cleanup evidence are retained.

Inspect the exact selection or verify routing without booting a simulator:

```sh
python3 scripts/ui-test-selection.py select smoke iPhone
python3 scripts/ui-test-selection.py select full iPad
python3 scripts/test-ui-test-selection.py
```
