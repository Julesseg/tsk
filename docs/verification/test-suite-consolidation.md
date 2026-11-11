# Test suite consolidation

## November 2026 reduction

The reviewed selection now runs three PR methods instead of twelve and thirty
nightly methods instead of eighty-five. Twenty-eight redundant methods are
deleted; twenty-seven distinct layout/system variants run only on demand.
The source target retains 57 methods. The previously undiscovered inline
`@MainActor` intent readback is also deleted. Core, Native, Apple-framework,
controller, native HID protocol and result-integrity checks remain.

The exact keep lists are `PHONE_SMOKE`, `NIGHTLY` and `ON_DEMAND` in
[the selector](../../scripts/ui-test-selection.py). Routing rejects unclassified
methods, missing selectors and duplicate cadences. Full now names the reviewed
nightly contract rather than every method compiled into the UI target.

| Removed UI repetition | Retained evidence |
| --- | --- |
| Decimal occurrence position repeating the same UI helper | Native `decimalOccurrencePositionSurvivesNativeEditingCompletionAndReopen`; ordinary occurrence circle success/failure stays nightly |
| Malformed occurrence completion/start and occurrence activity variants | Core/Native occurrence/activity checks, genuine occurrence-circle failure and inline row activity mutation |
| DEBUG startup intent action/readback tests | Apple Native actual `perform()` tests with durable storage; these UI fixtures never invoked external Shortcuts/Siri |
| Relative-date/arithmetic saved-view variants | Core and pinned Taskwarrior Native conformance; one raw-filter UI authoring/validation/result lifecycle stays |
| Waiting, carry-forward, midnight, Upcoming day-group and organization round trips | Core/Native date/view/persistence checks; actual row controls, bulk Apply and durable completion stay |
| Separate selection holds/toggles, Upcoming duplication/failure and last-result membership case | The retained gesture runs without native list IDs and covers sweep deselection/re-entry; Core selection identity and Native atomic membership checks remain, alongside nightly Apply failure/editor retention |
| Injected Calendar empty/access/error matrices | Core/controller/Native policies and real Calendar grant/deny/change/foreground journey; display/recovery/overflow UI stays on demand |
| Peer-completion Spotlight fixture | Apple Native received-encrypted-sync/common-effects/index regression; real system search/tap stays nightly |
| Separate URL add/readback | Current-tab/no-editor assertions join actual caller/callback creation and durable UUID readback |
| Four-configuration notification-control existence tour and duplicate Upcoming completion feedback | Real notification registration/delivery UI and controller checked-feedback lifecycle checks |
| Settings destination and Projects/color tours | Retained feature journeys reach their Settings destinations; screenshots did not assert colors |
| Standalone UIKit keyboard baseline control | Real product HID/focus journey nightly, annotation HID on demand and protocol/ownership host checks |

This deliberately reduces exhaustive per-view UI wiring: Today waiting captions,
Upcoming regrouping/duplicate-circle/view-change behavior, Projects-only routes
and detail dependency-cycle errors rely more heavily on host behavior checks.
Appearance/large text, geometry, animation drift, Project-menu stress/focus/scroll,
Calendar settings, permission revocation, detail activity/annotations, recurring
authoring/copy, stale Spotlight and failed callback delivery remain callable on
demand. These are accepted frequency/coverage tradeoffs, not equivalent assertions
proven by a different journey. Run the relevant on-demand cases when changing
those paths.

The retained bulk-date test drops its final repeated fresh-app screenshot pass.
The notification delivery test drops a 100-request capacity probe whose assertion
allowed any retained count from one through one hundred; it did not prove an
exact capacity or which tasks survived. Closed-app delivery and actual mutation
reconciliation remain. The native menu stress/retention and animation cases keep
their original loops, untouched intervals, assertions and deadlines on demand.

### Timing baseline and validation limits

[PR run 43016545565](https://github.com/Julesseg/tsk/actions/runs/43016545565)
passed twelve methods on 11 November. They totaled 1,159.0 seconds (19.3 minutes).
The three retained method durations totaled 408.2 seconds (6.8 minutes) in that
same run. This is a counterfactual selection comparison, before the assertion
joins; it is not a measured new-suite runtime. The original worker took 24.7
minutes, its producer 6.1 minutes and an execution queue added about 21 minutes.

[Scheduled run 42589919139](https://github.com/Julesseg/tsk/actions/runs/42589919139)
passed all eighty selected methods on 9 November at `8b7ae9b`. Summed method
time was 103.9 minutes across two parallel workers. Twenty-eight matching retained
methods cost 44.2 minutes there; the two newer retained bulk-date methods add
roughly 3.6 minutes using PR timings. Revisions and method bodies differ, so
roughly half the test execution is an estimate. Builds, setup, cleanup and queues
do not shrink proportionally. The incomplete 11 November nightly is excluded
from this baseline.

The two nightly workers retain nineteen workspace and eleven task/row methods.
Native HID, installed integrations and UI server/peer consumers remain together
in workspace. Smoke no longer starts a UI server/peer. The shared producer still
builds the server/probe for Native conformance and runs its real synchronization
fixtures.

Acceptance requires existing routing/ownership/gate regressions, signed test
product compilation, PR smoke and the reduced full selection at the exact
implementation head. Inspect selected/completed methods, skips, duplicates,
source/toolchain identity and native receipts, then measure actual execution and
wall time separately. No post-change runtime is claimed by this baseline.

## Earlier consolidation (historical)

The requested reduction targets expensive UI repetition rather than fast Core
coverage. Before consolidation, the successful iPhone smoke run on `08c5e4d`
(run 40511713919) spent 1,777.152 seconds executing 22 methods, excluding setup
and builds. Its iPad lane passed 17 methods before the cumulative execution
limit interrupted the next journey. The 169 Core tests took 0.053 seconds after
building in the recorded local run. No Core or Native test was removed.

## Merged or removed repetitions

| Previous coverage | Replacement | Reason |
| --- | --- | --- |
| Separate expansion/header and middle-row spacing tests | `testMiddleRowOpensSpaceAroundItsFixedHeader`, with shared expansion assertions also used by the edit round trip | One expansion/collapse checks header, checkbox, compact spacing and neighboring rows together. |
| Separate compact controls/date-surface journey | `testOutsideSaveValidationPickersAndDurableCompletion` | The durable journey already opens all three dates, priority and project. It now retains empty-project dismissal too. Re-selecting the same priority after readback was removed. |
| Separate long-title and lower-list keyboard/scroll journeys | `testLongTitleNearBottomKeepsKeyboardAndScrollingUsable` | One large-text, long-title, crowded-list case checks bounded title, keyboard avoidance, draft retention and actual list scrolling. |
| Separate title-edit/completion/relaunch journey | The row edit round trip now completes through task information and verifies the completed list after relaunch | Reuses the already edited and reopened task instead of creating another one. |
| Two annotation journeys calling the same helper | `testAddValidateEditAndReopenTimestampedAnnotations` | One journey retains empty-toolbar validation, first-note toolbar save, native command saves/editing, timestamps and durable two-note readback. The redundant UIKit Select All menu route is removed. |
| UI method checking only synchronization environment variables | Validation at the start of the real-server synchronization journey | Fixture configuration is checked where it is consumed, without a separate XCTest lifecycle. |
| Task creation repeated inside the Settings tour | `testPlacementAndEverySettingsDestination`; creation remains in the capture journey | The tour checks control placement, Settings destinations and editor cancellation without repeating typing/save/relaunch behavior. This also removes the duplicate keyboard-dismiss step that failed on run 40521701161. |

Declared UI methods fall from 73 to 67. Full iPad selection falls from 63 to 58;
the standalone phone-only title-edit method was never selected on iPad. All
other removed methods are covered by the joins above.

## Less work on every PR

Smoke changes from 22 iPhone + 19 iPad executions to 4 + 2. Share, widgets,
Spotlight, Settings tours, annotations and exhaustive appearance/accessibility
cases remain in nightly/manual full coverage. These are frequency changes,
not claims that those integrations passed. The smaller smoke still exercises
real-server synchronization on iPhone, plus the central task and adaptive iPad
workflows. Physical-keyboard journeys remain in full/nightly and focused
keyboard/text diagnostics. A green smoke run does not certify keyboard shortcuts.

On PR run40708413564, iPad's companion startup timed out before XCTest launched,
preventing all ordinary task tests from running. Smoke now selects no physical
keyboard cases and uses the normal XCTest path. Transport enablement is derived
from the selected cases using the same owner case definitions as native
acceptance; full and diagnostic keyboard cases still require the transport and
retain every assertion and deadline. This changes frequency, not native acceptance.

The same run's iPhone lane passed four of five methods. The row journey compared
a visible checkbox position172 against an earlier infinite baseline. Geometry
comparisons now require two finite, contained, stable snapshots within five
seconds before and after expansion. The one-point position assertion remains.

Smoke needs two Mac workers instead of four. Full retains its two disjoint
partitions per family. Portable harness regressions move from every Mac worker
to one Linux job; controller regressions run on one Mac worker. This removes
repeated checks and smoke build/fixture setup without increasing deadlines.

Typed-attribute creation and typed-value editing remain separate: one creates
all five definition types through UI, the other exercises actual values using
fixtures. Their setup overlaps, but their behavioral boundaries differ; joining
them would also risk the existing per-method limit. Calendar, notification,
Reminders and Spotlight cases retain their distinct permission, delivery,
peer-membership and stale-result boundaries.

The selection regressions verify exact smoke membership, full coverage,
partition disjointness/union, native case ownership, unknown-selector rejection
and synchronization peer requirements. Native CI must verify the changed
journeys and full coverage before acceptance. No post-change runtime reduction
is claimed until measured on a completed run.
