# MyApp

<!-- One-line description of your app. -->

## Agent skills

### Auto-dispatch of unblocked issues

When an issue closes as completed, `unblock-dispatch.yml` finds `ready-for-agent`
issues whose `## Blocked by` list is now fully closed and spawns a Paseo agent
session for each on the self-hosted Mac runner (capped, guarded by the
`agent-dispatched` label). See `docs/agents/auto-dispatch.md`.

## Conventions

### Conventional Commits — commit subjects *and* PR titles

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by a pre-command hook (`.agents/hooks/validate-commit-msg.py`). **PR
titles must match too.** Title PRs `<type>(<scope>)!: <description>` using the
same types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

### Logic lives in Core, UI stays thin

`MyAppCore` (in `Core/`) is a pure SwiftPM package: all business logic belongs
there, covered by `cd Core && swift test` — the fast loop that runs on any
platform. The `App/` target is a thin SwiftUI layer over it, verified by the
XCUITest suite. When implementing a feature, put the behavior in Core with unit
tests first, then wire the UI on top.

### Always implement the UI part of an issue — never ask

**If an issue requires UI work, implement it. Do not ask whether you should,
and do not skip, defer, or stub it.** The fact that you may not be able to run
the UI tests on the box you are on (cloud/web sessions cannot — see below) is
**never** a reason to leave it out, hand it back to the user, or ask for
permission. The correct action is always: write the UI code, push it, and let
CI verify it.

#### CI is the canonical UI gate (background, not a decision to revisit)

The `App · XCUITest (macOS)` job in `.github/workflows/ci.yml` is the
canonical, reproducible gate for the UI test suite, and it runs on every PR.
You **never** need to run the UI suite locally as a precondition for
implementing an issue.

Whether the box you are on can run the UI suite at all is **environment-
specific**, so it is not stated here as a flat fact. A startup hook
(`.agents/hooks/platform-guidance.sh`) reports it per session: remote/web
sessions run on Linux with no iOS simulator and cannot build the `App/` target
or run XCUITest; a developer's Mac has Xcode and *can* run the suite locally,
though doing so is slow and optional. Follow whatever that hook tells you.
