# Complete Task acceptance evidence

Issue: [#68](https://github.com/Julesseg/tsk/issues/68). This branch starts at
`bde53381202509fa9742dc77ff0b0fdbf4876953`, independently of unmerged #66/#67.
Prerequisite #65 is closed and PR #82 is merged. iPhone is canonical under
[ADR 0007](../adr/0007-iphone-only.md); historical iPad wording does not restore
retired iPad coverage.

## Contract and ownership

`tsk://complete?id=<full UUID>` accepts exactly one UUID and optional `x-success`
and `x-error` callback URLs. Unknown/duplicate parameters and working-set IDs
fail validation. Shortcuts accepts one task entity and returns the existing rich
entity: UUID, description, project, tags, priority, Scheduled, Deadline, Waiting
until, status and Open Task URL.

URLs validate target availability before saving foreground drafts. Both entry
points resolve the UUID again inside Core's mutation lease at execution; they
never write an entity snapshot. Deleted and missing targets return
`task_deleted` and `task_not_found` errors. Native retains immediate offline
persistence. The existing completion operation preserves independent dates,
unknown attributes, tags and annotations, clears active work on completion, and
leaves completion/modification history untouched on repetition. Occurrence
completion retains the shared atomic child/parent-mask transaction, conflict
checks and rollback safeguards.

Without callbacks, the URL opens the completed task in its containing list.
Ordinary tasks expand; completed occurrences open their existing read-only
information, preserving the restriction on editing occurrence history. Repeated
links refresh that presentation. Nested drafts participate in the root navigation
gate, reusing the focused fix from #67 without depending on its unmerged branch.
Valid drafts save first; invalid drafts remain editable and block the action.
Committed actions are never retried or undone when callback encoding/delivery
fails.

## Available evidence

| Seam | Evidence | Limits |
| --- | --- | --- |
| Core contract | 187 tests pass, including strict URL/callback validation, missing/deleted targets, independent attributes, active-work clearing and repeated completion at a later clock time. Existing occurrence integrity tests remain intact. | In-memory adapters do not prove disk or system delivery. |
| Native durable storage | Both host targets complete without failures: inventory 154 portable / 28 Apple methods, with 50 environment-gated skips overall. Extended actual `CompleteTaskIntent.perform()` tests return rich current values from a stale entity, reopen storage, reject deleted/missing targets and preserve repeated ordinary/occurrence history. Existing native atomic rollback tests pass. | Network/Taskwarrior, multiprocess, owned Spotlight and other environment-gated cases were skipped locally. Direct `perform()` is distinct from Shortcuts invocation. |
| App controller | 74 host tests pass, including nested panel/draft registration and capture validation. The nested gate test failed on main before the fix. | Host controller tests do not deliver physical input or installed URLs. |
| App build | Signed arm64 simulator app, extensions and UI tests build. Intent artifact validation passes for shared entitlements, URL registration, four App Shortcuts and rich entity metadata. | Initial generic multi-architecture build failed against the arm64 bridge; corrected to the CI arm64 build settings. Builds alone are not runtime evidence. |
| Installed URL system | iPhone 18 Pro / iOS 27.0: both new XCUITest methods pass, 2/2 without skips, 284.326 seconds. Caller app opens actual URLs and receives structured results. Coverage includes rich results, repeated completion/reveal, invalid nested draft retention, missing-target no-save behavior, failed delivery, occurrence/read-only reveal, errors and durable relaunch. | Focused local runtime, not the complete canonical iPhone suite or exact-head CI. |
| Actual Shortcuts system | Installed Shortcuts discovers Complete Task, selects the uniquely named verification entity and runs it. System displays “Completion saved locally: Issue68 Shortcuts verification”. Relaunching tsk shows that task in Done, preserving project and both dates. | One manually exercised ordinary task on simulator; no Siri voice, physical device, account, signing/distribution or every error/occurrence combination in Shortcuts. Rich fields are asserted at Native and installed URL seams. |
| Test selection | All 16 selection/partition assertions pass. Full coverage includes 82 methods, split 45 workspace / 37 task-row; smoke remains 8. | Mock runner tests encounter the installed machine-wide lease helper and time out waiting for their fake device; stopped only this task's runs. CI's Linux environment runs the complete script. |

The initial controller invocation omitted `TSK_TASKCHAMPION_LIBRARY` and failed
four native-backed cases; the correctly configured full run passes. The first
device screenshot request failed, then succeeded after rediscovery. Manual deep
link startup required accepting the system Open in tsk prompt. These failures
were kept distinct from product assertions.

The focused result is `.build/issue-68-url.xcresult`; logs and screenshots are
local build artifacts. The mobile screenshot report lives on this Mac at
`/Users/julesseguin/.local/share/ui-reports/tsk/agent-issue-68/2026-11-11-complete-task.html`
(274,815 bytes). Its Shortcuts Before/After compares execution on the same
implementation, not main versus branch. The synthetic occurrence fixture omits
its child recurrence rule, so read-only information displays the existing
preserved-value warning; completion still exercises supported parent/index/mask
bookkeeping.

## Independent review

Two native Codex children reviewed the frozen baseline diff independently.
Provider/settings were verified as Codex, inherited `gpt-6.1-sol`, high reasoning,
default service tier.

- Standards: no documented breaches; one minor test-quality finding fixed by
  asserting the parsed enum directly instead of its debug text.
- Spec: two findings fixed: use TaskAttributes' entry-array fixture encoding,
  and validate missing/deleted targets before saving unrelated drafts. Core still
  re-resolves the identity when the action executes. Installed tests passed after
  both fixes.

## Acceptance still pending

PR smoke and manually dispatched full iPhone CI must be checked at the published
head. Green smoke does not establish full acceptance. No merge is authorized.
The owning top-level thread retains PR babysitting; later sequential issues are
launched only by the coordinator.
