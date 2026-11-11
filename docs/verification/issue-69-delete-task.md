# Issue 69: Delete Task automation

Delete Task accepts one task entity in Shortcuts or one full UUID through
`tsk://delete?id=<UUID>`. It immediately marks the task deleted, preserving
identity, unrelated attributes, annotations and synchronization operations.
Completed tasks retain their end time. Repetition returns the saved deleted
record without another mutation. Missing identities fail clearly. Recurring
templates remain protected; occurrence deletion atomically changes its series
position to `X`, including completed occurrences, with the existing integrity,
conflict and rollback checks.

Core owns deletion and rejects deleted Open targets. Existing Core edit and
completion guards and Find's All exclusion apply to deleted records. Native
commits the status through TaskChampion before acknowledging offline success.
The rich task entity and URL callback report `status: deleted`; their shared
Open Task URL identifies the preserved record but Open rejects that deleted
identity. A callback failure never undoes or retries a committed deletion.
Without callbacks the app confirms local deletion and leaves the deleted
editor. Valid drafts save first; invalid drafts block deletion and remain
editable. Missing targets are checked before committing an unrelated draft.
Nested linked editors reuse the focused shared navigation gate from #67/#68.

## Dependency and scope

This branch originally started at unmerged #66 / PR #91, commit
`e0ad2959435d60a77e68d101dfc63920e9712537`, by explicit user instruction.
The PR targets main, so its diff includes inherited Find changes until #91
merges. After rebasing onto main at `7c8a7be`, the prerequisite is reapplied as
`8e21b39`. Review #69's own changes with `git diff 8e21b39...HEAD`.
#67 / PR #92 and #68 / PR #94 implementation/open-PR gates were already met;
this branch does not modify their branches or take over their watches.
Main was fetched before publication and refreshed by rebase on 2026-11-12.
The prerequisite remains unmerged; its branch was not modified.

## Original verification at 27bbc10

- Core contract: 193 tests pass on macOS and Swift 6.0.3 Linux. Delete coverage includes strict singular
  UUID parsing/callbacks, soft deletion, repetition at a later clock, completed
  and missing targets, preservation, Find All exclusion, rejected edit/complete/
  Open, storage failure, protected templates and atomic occurrence safeguards.
- Native durable storage: both host targets pass, with environment-gated cases
  explicitly skipped (156 portable / 31 Apple methods inventoried, 51 gated
  skips overall). Direct `DeleteTaskIntent.perform()` returns rich saved
  fields and reopens the durable deleted record offline. The persistent
  occurrence test injects a real SQLite transaction failure, verifies rollback,
  then verifies mask `X`, retained history and no additional operations on repeat.
- Peer synchronization: an isolated real taskchampion-sync-server 0.7.1 run
  passes `deleteIntentSynchronizesSoftDeletedIdentityAndHistoryToPeer`. A peer
  first sees pending, then deleted, retaining UUID, opaque data and annotation;
  Find All excludes it. This is direct intent execution plus real synchronization,
  distinct from system Shortcuts invocation.
- Controller: all 74 host tests pass, including the nested panel/draft gate.
- Build: signed arm64 simulator build-for-testing passes. Artifact validation
  confirms five App Shortcuts, one required Delete entity, rich entity output,
  URL registration and shared app/extension entitlements.
- Installed URL delivery: iPhone 18 Pro / iOS 27.0, two focused XCUITest methods
  pass without skips (179.568 seconds). An installed caller launches actual URLs
  and receives rich success/repeat/Find callbacks. Tests verify durable relaunch,
  rejected Open, missing errors, retained invalid linked draft, valid-draft save,
  success confirmation and absence of a deleted editor. After the Spec review
  fix, the extended callback method passes again with an already-open Find
  sheet; it becomes empty and cannot open the deleted identity. Find destinations
  re-resolve the store's current records, which synchronization also updates.
  This system regression delivers deletion by URL; peer-driven Find UI was not
  separately exercised.
- Actual Shortcuts: the installed Shortcuts app discovers Delete Task, selects
  one verification entity and runs it twice. Both runs show “Deletion saved
  locally: Issue69 Shortcuts verification”. Relaunching tsk leaves exactly one
  of two same-named verification tasks, preserving the unrelated entity.
- Selection: all 16 selection assertions pass. Full iPhone coverage contains
  84 methods (47 workspace / 37 task-row); smoke remains 8. Mock runner cases
  wait on the installed host lease helper for their fake device; only this
  session's waiting processes were stopped. CI/Linux owns that runner check.

The Core red test initially failed because deletion/Open APIs were absent.
The first Native intent run exposed the bridge's unsupported deleted transition;
it passes after permitting the soft-delete transition. Nested throwing test
macros were separated for Swift 6.0.3 compatibility. A failed simulator bridge
invocation omitted rustup from PATH; the corrected build passes. The first
Device screenshot failed and succeeded after the instructed rediscovery.

Runtime used one acquired simulator lease. No simulator was initially booted;
the owned iPhone was shut down and its lease released immediately after runtime.

No iPad claim is made: ADR 0007 defines iPhone acceptance. Local focused runtime,
builds, direct intent execution and real Shortcuts each establish different
boundaries. Full exact-head iPhone CI remains required; smoke alone is not full
acceptance. Siri voice, physical device/distribution provisioning, account
behavior and suspended-process behavior were not verified. URL persistence and
callback-error paths share the existing contract; not every failure combination
was manually repeated in Shortcuts.

## Independent review and visual evidence

Native Codex children independently reviewed Standards and Spec against the
staged #69 diff from e0ad295. Provider/settings were verified as Codex,
gpt-6.1-sol, high reasoning, default service tier. Standards found no actionable
issues. Spec found one stale Find snapshot path. The fix filters current saved
records and re-resolves detail destinations; the extended installed-URL test
passes. Its first run displayed the correct empty state but queried an AX
container UIKit did not expose. Assertions now check the actual visible empty
message and missing row, preserving deadlines; the inherited empty-state check
uses that same user-visible assertion.

The screenshot report lives on this Mac at
`/Users/julesseguin/.local/share/ui-reports/tsk/agent-issue-69/2026-11-11-delete-task.html`.
It is 186,571 bytes and contains real Shortcuts, URL confirmation/callback and final Find captures.
The Shortcuts before/after compares runtime states on the implementation, not
main versus branch. Phone-width loading, image enlargement and overflow checks
pass in a headless browser; missing intermediate captures are listed in the
report. Runtime assets and xcresults remain local under `.build/`.

## Rebase verification (2026-11-12)

Rebased onto main `7c8a7be`, retaining the Find prerequisite as `8e21b39`.
The recurrence resolution preserves main's shared occurrence-mutation validation
and adds deleted status/mask handling through it. Current staged bulk-selection
behavior and main's coverage consolidation remain intact. Find and Delete URL
journeys have explicit nightly registration; old test classes and removed cases
were not restored. The resulting inventory is 61 retained cases: 34 nightly
(23 workspace / 11 task-row), 27 on demand, and 3 smoke. The original 84-case
results above describe the earlier source and do not certify this rebased head.

New exact-head CI is required after publication. The prior input/lifecycle
failures remain historical evidence until reproduced or cleared on current
source; rebasing alone is not a claim that all remaining failures are fixed.

Rebase checks pass: 207 Core tests; both Native host targets (158 portable / 31
Apple methods inventoried, 51 gated skips); 76 controller tests; coverage
selection/routing/execution checks; signed arm64 simulator build-for-testing and
intent artifact validation. No simulator was booted for this rebase. Native
runtime acceptance and the remaining failure investigation require new CI at
the rewritten head.
