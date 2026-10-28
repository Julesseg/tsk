# Test suite consolidation

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
