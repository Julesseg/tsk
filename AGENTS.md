# tsk

A native iPhone Taskwarrior client. `Core/` owns task behavior; `Native/`
connects TaskChampion and system services; `App/` contains thin SwiftUI app,
Share and widget interfaces. Shared storage, encrypted sync and task workflows
are implemented. Use canonical iPhone XCUITest for runtime verification;
source, host tests and generic builds do not establish system delivery,
physical input, account behavior or distribution provisioning.

## Agent skills

### Issue tracker

Track issues and specs in `Julesseg/tsk` GitHub Issues using `gh`. Read
`docs/agents/issue-tracker.md` before creating or managing tickets.

### Triage labels

Use the five default triage labels. Read `docs/agents/triage-labels.md` before
triaging or changing issue labels.

### Domain docs

Use a single-context layout: root `GLOSSARY.md` and `docs/adr/`. Read
`docs/agents/domain.md` before exploring domain concepts or architecture.

### Auto-dispatch of unblocked issues

When an issue closes as completed, `unblock-dispatch.yml` finds `ready-for-agent`
issues whose `## Blocked by` list is now fully closed and starts a T3 Code
thread for each on the self-hosted Mac runner (capped, guarded by the
`agent-dispatched` label). See `docs/agents/auto-dispatch.md`.

### Session orchestration

In T3 Code, read `docs/agents/t3-code.md` before delegating, handing off,
running a worker/verifier loop, watching a PR, or operating a simulator. Its T3 mechanics
take precedence over Paseo commands in shared instructions and skills.
Reuse this registered project and the thread's worktree for helpers.
Schedules and heartbeats remain in Paseo.

## Conventions

### Conventional Commits — commit subjects *and* PR titles

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by a pre-command hook (`.agents/hooks/validate-commit-msg.py`). **PR
titles must match too.** Title PRs `<type>(<scope>)!: <description>` using the
same types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

### Logic lives in Core, UI stays thin

`TskCore` (in `Core/`) is a pure SwiftPM package: all business logic belongs
there, covered by `cd Core && swift test` — the fast loop that runs on any
platform. The `App/` target is a thin SwiftUI layer over it, verified by the
XCUITest suite. When implementing a feature, put the behavior in Core with unit
tests first, then wire the UI on top.

### Text-size verification priorities

Use standard Dynamic Type for UI work, screenshots and focused verification.
Add targeted runs or investigate enlarged/accessibility text variants only when
the user explicitly asks. Existing full CI coverage can run as configured;
treat failures isolated to those variants as non-blocking for other work,
report them briefly and continue with standard-size behavior.

### Always implement the UI part of an issue — never ask

**If an issue requires UI work, implement it. Do not ask whether you should,
and do not skip, defer, or stub it.** The fact that you may not be able to run
the UI tests on the box you are on (cloud/web sessions cannot — see below) is
**never** a reason to leave it out, hand it back to the user, or ask for
permission. The correct action is always: write the UI code, push it, and let
CI verify it.

#### CI is the canonical UI gate (background, not a decision to revisit)

The iPhone `App · XCUITest (macOS)` check runs focused smoke coverage
on PRs with non-documentation changes, alongside all Core and Native tests.
Documentation-only PRs and pushes use lightweight checks without test builds.
Full UI coverage runs nightly and through manual dispatch. Read
`docs/verification/ci-test-tiers.md`
when changing CI coverage or verifying a workflow outside the smoke selection.
You **never** need to run the UI suite locally as a precondition for implementing
an issue.

Whether the box you are on can run the UI suite at all is **environment-
specific**, so it is not stated here as a flat fact. A startup hook
(`.agents/hooks/platform-guidance.sh`) reports it per session: remote/web
sessions run on Linux with no iOS simulator and cannot build the `App/` target
or run XCUITest; a developer's Mac has Xcode and *can* run the suite locally,
though doing so is slow and optional. Follow whatever that hook tells you.
