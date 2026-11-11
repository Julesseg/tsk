# Issue 70 verification

Open Task and Open View use Core destination resolution, Native task/view storage and App Intents, and the normal iPhone workspace. The app saves valid edits before navigation, retains rejected drafts, opens a temporary workspace without changing favorites, and restores the originating list and navigation path through Back.

## Acceptance evidence

| Criterion | Evidence |
| --- | --- |
| Fresh task entity/full UUID, containing list, expansion and return | Core `navigationResolvesCurrentTaskAndContainingListAndRejectsDeletedIdentity`; installed `TaskNavigationUITests.testInstalledOpenTaskURLUsesFreshRecordExpandsContainingListAndReturnsWithColdMissingIdentity`; actual Shortcuts Open Task entity execution; manual valid URL after closing the app |
| Completed, deleted and missing identities | Core pending-to-completed and deleted/missing checks; completed-occurrence Core/controller regression preserves read-only mutation rights; installed completed expansion and cold missing error |
| Native view picker and strict named URLs for all categories | Core strict URL parsing; Native durable picker test; installed URL loop for Today, Upcoming, All unfinished, Done, Projects and exact project; real Shortcuts discovery/picker and Open View Done execution |
| Stable saved UUID, rename/missing and hidden favorites | Native persistent saved-view query/rename/delete test; installed hidden saved-view rename/delete journey and unchanged favorite tabs; exact-project availability checked in Core |
| Valid edits save; invalid or failed saves retain drafts/errors | Controller current/nested drafts, blank capture, invalid tags and injected persistence failure; installed invalid-title error callback followed by corrected-title save and successful view callback |
| Picker, keyboard, accessibility and single expanded row | Existing row editor and picker paths retained; controller retention assertions; installed one-expanded-row journey, native controls and accessible Back/row actions. Hardware keyboard and VoiceOver were not manually exercised in the external workspace |
| Actual callback outcome and foreground/background separation | Installed caller fixture receives navigation failure for an invalid draft and success only after Done navigation; Native foreground handler propagates navigation errors; Add/Find/Modify/Complete/Delete stay background. Real Shortcuts execution uses the app handler, not custom-URL wrapping |
| Return context | Installed project → external Done → Back restores Work.Travel breadcrumb and task list; normal keyboard selection clears external titles |

## Local checks

- Core: 189 tests passed.
- Native: 133 enabled methods passed; 50 fixture-dependent methods skipped. The missing fixtures include the pinned Taskwarrior/server/multiprocess and owned Spotlight environments. This local invocation is not full Native CI acceptance.
- Controller packages: 76 methods passed, no skips. The keyboard-registration target has no host-discovered cases in this configuration.
- UI selection checks: 24 passed. The original full selection contained 83 iPhone methods. After rebasing onto the reviewed coverage consolidation, all three navigation methods are explicitly nightly: full now contains 37 methods (26 workspace, 11 row editing), including merged Find and Modify coverage, smoke contains 3, and the 27 on-demand methods remain on demand.
- Signed arm64 simulator `build-for-testing` passed. Produced App/Share/Widget entitlements, six App Shortcuts, URL registration and required entity pickers passed `verify-intents-artifact.py`.
- Installed iPhone navigation XCUITest: 3/3 passed, no skips; `.build/issue70-navigation-final.xcresult`. This is focused local system coverage, not exact-head smoke or full CI.
- Real Shortcuts discovery, native view/task pickers and both foreground actions executed on iPhone 18 Pro / iOS 27.0. A valid task URL also opened after closing the app. Only the owned temporary shortcut was removed; pre-existing shortcuts were preserved.
- Both independent Codex review axes completed. Standards found no hard violations and two duplication judgments, both fixed. Spec found completed-occurrence, stale external-title and project-return-path defects, all fixed; the project return fix was rerun in XCUITest.

The initial cold task UI test used an isolated UUID while an OS cold launch correctly selected the normal dataset, producing a missing-task error. The automated case now verifies warm isolated task navigation and cold missing handling. Manual cold valid URL verification used the normal saved dataset. The first real Shortcuts experiment rejected `OpenURLIntent` with `The provided URL scheme tsk is unsupported; launch is prohibited`; replacing that adapter with foreground app navigation passed actual execution.

## UI report

The single-file report is on the developer's Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/agent-issue-70/20261111-issue70.html`
(406,977 bytes). It contains 23 inspected screenshots in four sections. At 390 CSS pixels, all 23 decode, there is no horizontal overflow, and tap-to-enlarge works.

Before/after means the starting and resulting journey states on the changed build. No base-revision visual comparison was captured. Screenshots precede the final host-verified blank-capture retention guard; that guard adds validation without changing layout. Completed-occurrence read-only expansion, persistence-failed drafts, nested panels, every Shortcuts view category and hardware-keyboard/VoiceOver journeys have no dedicated screenshots. Those limits are listed inside the report.

## Remaining acceptance

Exact-head PR smoke and manual full iPhone CI must still finish and be audited. Local host tests, direct `perform()` calls and signed builds do not establish Shortcuts discovery/execution or installed URL delivery; the separate actual-system evidence above covers only the stated journeys. Full Native fixture coverage, the current nightly iPhone selection, physical-device behavior and distribution provisioning are not claimed here. iPad coverage is retired under ADR-0007.

## Rebase onto merged Find (2026-11-15)

Included `main` at `910cf001383cbd0d84b6c8734d3c083305b5997b` and combined Find with Open Task/View URL parsing, callback payloads and intent metadata checks. A successful Open destination dismisses the Find results presentation after the common draft gate; the installed task-navigation case now starts from an actual Find results sheet. Foreground navigation explicitly rejects background Find requests. The original assertions remain.

Rebase checks: Core 208 passed, controller 78 passed, UI-selection 17 passed; Native 137 enabled methods passed with the same 50 fixture-dependent skips. Signed arm64 simulator test build passed. App metadata contains all six shortcuts, fourteen Find inputs and the Open Task/View entity pickers. The full local artifact verifier cannot complete because this Xcode build skipped Widget App Intents extraction (`no AppIntents.framework dependency found`); Widget sources are unchanged by this PR and canonical CI retains the complete verifier. This local gap is not reported as a metadata pass.

Previous-head evidence remains failed: `43189595158` on `b0b0a88` failed bulk selection admission and XCTest app termination; `43189669983` passed the workspace shard (including navigation) but lost the owned row-editing simulator and its result bundle. No tests were retried or weakened to turn those results green. Fresh-head required checks and full iPhone coverage must be assessed separately. Auto-merge is authorized to use the repository's required Core Linux and App XCUITest checks, with merge method and no bypass.

## Rebase onto merged Modify (2026-11-16)

Included `main` at `610df1c7f9686c38932322fd3acce8832d13c7f8` after #92 merged. Preserved strict Modify fields, clear/tag controls, durable rich callbacks and nested draft gates. Modify without callbacks now reveals its saved task through the same normal containing-list/Back route as Open Task; Find retains its independent list results and callback payload. Reschedule stays retired. Identical nested-gate declarations were deduplicated without removing main's regression test.

Checks on the combined source: Core 213 passed; controller 79 passed; Native 139 enabled methods passed with 50 fixture-dependent skips; UI-selection 17 passed; signed arm64 simulator test build passed. App metadata verifies all six current actions, fourteen Find inputs, fourteen Modify inputs, Open entity pickers and absence of retired Reschedule/Create. The previously recorded complete local Widget-metadata verification gap remains separate from these app checks. Standard Dynamic Type remains the verification priority; no enlarged-text rerun was added.

Full/nightly now retains 37 methods (26 workspace / 11 row editing), including both Modify and all three Open navigation cases; smoke remains 3 and on-demand remains 27. Fresh exact-head required/full CI must establish the new integration result. Previous-head successes and failures remain historical evidence, not acceptance of this rebased source.

## Rebase onto merged Complete (2026-11-16)

Included `main` at `3d2bd74f7f713938048f230bece29d95060b0598` after #94 merged. Complete retains its deleted/missing-target preflight before draft persistence, durable rich callbacks, repeated task presentation and read-only occurrence information. Open Task/View retain their independent normal containing-list route and actual navigation callbacks. Foreground navigation rejects Complete along with the other background data actions. No existing completion assertions were changed.

Combined-source checks: Core 216 passed; controller 79 passed; Native 139 enabled methods passed with 50 fixture-dependent skips; UI-selection 17 passed; signed arm64 simulator test build passed. The complete artifact verifier now passes App/Share/Widget entitlements, embedded Widget configuration/completion, six App Shortcuts, fourteen Find inputs, fourteen Modify inputs, rich task fields and both Open entity pickers. This successful build resolves the earlier local Widget-metadata extraction gap; the earlier failed invocation remains historical evidence. No local runtime or new visual/Shortcuts delivery claim was added by the rebase.

Full/nightly retains 39 methods (28 workspace / 11 row editing), including both Complete, both Modify and all three Open navigation cases. Smoke remains 3 and on-demand remains 27. Required smoke and separate full CI must establish the new head's result; the previous `2c5bdb2` full run `43774527080` was still running when this rebase was verified.

## Rebase onto merged Delete and smoke diagnosis (2026-11-16)

Included `main` at `7b436a5cc390e51fb6d71a9fdfcb5809efdfbcb5` after #95 merged. Delete retains its preflight before draft persistence, saved-local callbacks, stale task/Find-result cleanup and deletion acknowledgement. The Native bridge was rebuilt for host and simulator to include main's occurrence-deletion fix. Foreground Open rejects background Delete, and artifact checks retain all seven current Shortcuts, including Delete. Existing Delete/Complete UI assertions remain unchanged.

The previous head `aa2a6fd` failed required smoke run `43785667608`: 2 passed, 1 failed, no skips. The failing bulk-selection assertion was `1 selected` versus `3 selected` at `TaskBulkSelectionUITests.swift:40`; the macOS check is its aggregate failure. The original log, result bundle, recording, synthesized-event attachment and execution receipt are retained under `.build/pr96-aa2a6fd-failure` and `/tmp/pr96-aa2a6fd-smoke.log`. The producer used merge commit `535caf0885548d04e6f02d7b7a11d78a1c5819ec`, whose tree `9b63287a3c410f8a360c63f12f77e3d6a5ba42db` exactly matches `aa2a6fd`. The recording confirms only the first selected row. The synthesized held drag moved from `(60,132)` to `(60,196)` after a 0.8-second hold and retained the 2-second end hold. This confirms the requested event, not app receipt of every movement. The root cause remains unproven.

The runtime proof attachment originally followed the count assertion, so this failure prevented its capture. Moved that attachment before the unchanged count assertion to retain gesture/refresh evidence if it recurs. No gesture, assertion, deadline, suite membership or product selection behavior was weakened. No same-head rerun was issued for the superseded source. Its separate full run `43785699924` was pending during diagnosis; that pending result is not acceptance.

Combined-source checks: Core 220 passed, controller 79 passed, Native 141 enabled methods passed with 51 fixture-dependent skips, UI-selection 17 passed, signed arm64 simulator test build passed, and the complete App/Share/Widget metadata verifier passed. Full/nightly now retains 41 methods (30 workspace / 11 row editing), smoke 3 and on-demand 27. No new local runtime, visual, Shortcuts delivery or full-acceptance claim is added. New-head required and full CI remain separate gates.
