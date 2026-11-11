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
| Actual callback outcome and foreground/background separation | Installed caller fixture receives navigation failure for an invalid draft and success only after Done navigation; Native foreground handler propagates navigation errors; Add/Find/Complete/Reschedule stay background. Real Shortcuts execution uses the app handler, not custom-URL wrapping |
| Return context | Installed project → external Done → Back restores Work.Travel breadcrumb and task list; normal keyboard selection clears external titles |

## Local checks

- Core: 189 tests passed.
- Native: 133 enabled methods passed; 50 fixture-dependent methods skipped. The missing fixtures include the pinned Taskwarrior/server/multiprocess and owned Spotlight environments. This local invocation is not full Native CI acceptance.
- Controller packages: 76 methods passed, no skips. The keyboard-registration target has no host-discovered cases in this configuration.
- UI selection checks: 24 passed. The original full selection contained 83 iPhone methods. After rebasing onto the reviewed coverage consolidation, all three navigation methods are explicitly nightly: full contains 33 methods (22 workspace, 11 row editing), smoke contains 3, and the 27 on-demand methods remain on demand.
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
