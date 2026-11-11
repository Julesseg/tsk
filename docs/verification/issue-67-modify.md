# Modify Task verification

Issue #67 adds named atomic Modify inputs to native Shortcuts and `tsk://modify` and removes the standalone Reschedule action. iPhone is canonical under ADR 0007. #66's branch is not part of this change; Delete, Complete and further navigation work remain in their own issues.

## Acceptance evidence

| Requirement | Evidence |
| --- | --- |
| Seven named fields; omission/empty preservation; explicit clears | Five Core Modify tests, two persistent intent tests, built intent metadata, installed URL tests. Real Shortcuts showed the parameter sheet, changed Description, cleared Project, and preserved omitted tag/priority/date values after app relaunch. |
| Add/Remove/Replace/Clear tags, Add default, byte-exact identity, conflicts | Core and persistent intent tests include composed/decomposed tag spellings. Installed URL XCTest runs all four operations and conflicting clear rejection. Shortcuts displayed Add as the default. |
| Exactly one entity/full UUID | Core URL rejection tests cover numeric/partial/missing/duplicate IDs and filters. Real Shortcuts selected one saved task entity; installed URL callbacks returned its durable UUID. |
| Atomic validation/persistence, unknown fields, task states, recurrence guard | Core and persistent intent readback cover completed/deleted/missing targets and byte-exact opaque attributes. Existing occurrence-intent tests now use Modify. Native SQLite operation-log failure injection rejects a multi-field Modify and verifies unchanged records/operation count; Core's failing-storage boundary also verifies no partial changes. |
| Offline acknowledgement, callbacks and draft-safe reveal | No network is needed for persistent intent saves. Installed iPhone URLs deliver and decode actual callback JSON, verify independent timestamps and durable relaunch readback. No-callback Modify settles valid edits and reveals the saved task. The extended journey retains both invalid linked-row drafts and nested Edit-sheet drafts. |
| Remove Reschedule | Removed intent/date-role adapter and shortcut registration; migrated production test fixtures and persistent tests to Modify. Signed app metadata admission requires Modify and rejects the retired action. The remaining action set is completed by the separately tracked issues. |
| Canonical UI and visual evidence | Two installed URL iPhone methods passed; after the independent review fix, the extended navigation method passed again. An actual Shortcuts run returned Saved locally, followed by ordinary app readback. The mobile report contains 11 inspected captures with explicit missing-capture notes. |

## Local results

- Core: 189 tests passed.
- Native: 134 methods executed and passed; 50 fixture-dependent methods skipped (real sync server/Taskwarrior/owned Spotlight and multiprocess integration prerequisites). This is available host coverage, not complete canonical Native CI.
- Controller packages: 74 tests passed, including a new red/green regression for root visibility of nested linked-store panels/draft validation.
- Signed arm64 generic iPhone simulator build-for-testing and intent/App Group metadata admission passed. Build success does not establish runtime delivery or provisioning.
- iPhone 17, iOS 27.0: installed URL tests 2/2 passed in 195.770s. After sharing nested navigation ownership, the extended active-edit method passed 1/1 in 117.703s. Results are under `.build/issue-67/modify-ui.xcresult` and `modify-nested-ui.xcresult` on the implementation machine.
- UI selection: 24 routing checks passed; full coverage now discovers 82 iPhone methods (45 workspace, 37 row-editing), with the two added URL journeys outside smoke.
- Same-provider independent Codex reviews: Standards 0 findings; Spec 1 nested draft-gate finding. Fixed by sharing gate ownership across linked stores, with host and installed iPhone regressions passing. The fix was assessed and verified by the parent; the children reviewed the original frozen diff.

## Evidence limits

Real Shortcuts verification exercised discovery, native parameters, entity selection, Description, explicit Project clear, omitted-value preservation and a durable acknowledgement/readback. Every other field, tag mode, task-state error and failure path was not manually exercised through Shortcuts. Core/persistent and installed-URL coverage are identified separately above. Direct `perform()` tests do not establish Shortcuts discovery or execution on their own.

Full exact-head iPhone CI is required for acceptance and will be dispatched on the PR head; PR smoke alone does not cover these system journeys. Neither full CI nor production-like sync/physical-device/Siri/background/locked-device/distribution provisioning is established by these local checks. The report lacks a base-revision Reschedule screenshot and complete lower-clear-control captures; its before/after task pair uses the same changed build before/after the action.

Local-only report: `/Users/julesseguin/.local/share/ui-reports/tsk/agent-issue-67/20261111-modify.html` (343,407 bytes). All 11 images loaded at a 402px viewport, no horizontal overflow, and image enlargement passed in headless Chrome. Both simulator reservations were finished, their device shut down and Device panel closed. The task and temporary Shortcuts workflow used for manual verification remain on that simulator; earlier fixture tasks/shortcuts were left intact.

## Rebase onto calendar visibility changes

Rebased onto `8206233` after #93 merged. Conflicts were confined to the two UI-count files: retained main's calendar case plus both Modify URL cases, giving 83 full iPhone methods (46 workspace / 37 row-editing). Range-diff confirmed no other change to the Modify implementation.

Post-rebase local checks: Core 192 passed; controller 76 passed; all 16 selection-planning tests passed. Eight mocked runner cases entered the host's real simulator-lease helper and waited on another session's reservation; stopped only this task's waiting processes. The initial broad run timed out those cases. Native/generic build attempts were stopped during severe host contention; fresh CI is required for the updated head. No simulator was booted for this rebase.

Prior-head full run `42938791846` failed two unrelated UI assertions (automatic-sync Settings reveal and occurrence row tag-input appearance); both new Modify URL methods and native-automation methods passed. Smoke attempt 1 failed held-selection activation; the one targeted retry passed that case but failed initial editor appearance in another bulk-selection case. Preserve those failed verdicts. They are historical results for `cf1d1f9`, not acceptance of the rebased head.

## Rebase onto staged bulk selection

Rebased onto `b4ca072` after #86 merged. Retained main's staged Apply/cancel selection behavior, quarter-second selection admission, recurrence mask path and expanded UI/keyboard coverage. Only the two coverage-count files conflicted; full selection now contains 87 methods (46 workspace / 41 row-editing), with 12 smoke methods. Range-diff showed no additional Modify behavior change.

Post-rebase Core 203, controllers 76, Native 136 executed methods and all 16 selection-planning tests passed. Native retained 50 fixture-dependent skips. Signed arm64 simulator build-for-testing passed; its incremental artifact lacked widget intent metadata, so a clean rebuild was performed and passed all intent/App Group admission checks. No simulator was booted. The eight mocked runner cases remain outside these local results because they enter the host lease helper; canonical CI supplies the full routing/runtime gate.

The superseded `d3ec39c` full run `43012743602` passed the workspace shard and failed one row-editing assertion: the enlarged-text occurrence test's tag input did not appear at line 562. The standard-size Modify URL/navigation methods passed in workspace. Retain the failed overall verdict; fresh exact-head CI is still required. The current AGENTS.md makes enlarged/accessibility variants non-blocking for other work while preserving configured CI coverage and reporting their failures.

## Rebase onto consolidated UI coverage

Rebased onto `7c8a7be` after #97 and #98 merged. Preserved main's test fixes, explicit nightly/on-demand registration and three-method smoke suite. Registered both existing Modify URL journeys as nightly system coverage: 32 nightly methods (21 workspace / 11 row-editing), 27 on-demand, 59 retained overall. The Modify implementation and its assertions are unchanged; the auto-merged URL class retains main's removed duplicate Add scenario.

Post-rebase Core 203, controllers 82, Native 136 executed methods and all 17 UI routing tests passed. Native retains 50 fixture-dependent skips. All 11 CI execution tests passed. Signed arm64 build-for-testing passed; the incremental product again lacked widget intent metadata, so a clean build was performed and passed intent/App Group admission, including Modify and retired-Reschedule checks. The first controller invocation omitted the native-library environment and failed four storage-dependent cases; rerunning with the built host library passed the full package. The first routing invocation exposed unregistered Modify selector names during resolution; corrected the registrations to the actual methods and reran the complete routing suite successfully. No simulator was booted or reservation used.

Superseded head `1006cd9` remains failed evidence: smoke passed 11/12, with XCTest failing to terminate the app during bulk-selection teardown after the final assertion. Full run `43039461924` failed Share app termination, a Reminders date-switch input acknowledgement, two bulk-selection assertions, long-title row editing and enlarged-text occurrence tags. Both Modify URL methods passed. The one Native Linux retry failed the same Ubuntu DNS/package setup before any Native tests ran; no further retry was attempted while the failure persisted. These historical results do not establish acceptance of the rebased head. Fresh smoke and full nightly-selection CI are required; on-demand methods and external Shortcuts/physical-device evidence retain their stated limits.
