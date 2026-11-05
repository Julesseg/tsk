# T3 Code orchestration

This project's interactive sessions and issue dispatch use T3 Code. Existing
Paseo schedules and heartbeats remain there. Apply this document when running
inside T3; sessions launched by Paseo retain their Paseo orchestration.

## Project and worktrees

Reuse the registered `tsk` project. Independent changes use a T3-managed
worktree based on the current remote default branch. A separate checkout is
not a separate registered project. Helpers run in the current thread's
worktree, with separate build output paths when concurrent work requires it.

`t3.json` shares project actions. Import its actions in Settings → Projects
when setting up another environment. Core tests need no worktree setup;
build the native bridge before building the app. Actions run on demand and
leave simulator booting to runtime verification.

For Linux sessions with an SSH Mac device source, use the
[remote iOS workflow](../remote-ios.md) for source sync, Xcode builds,
installation and focused UI tests. Device streaming alone does not sync code
or route project build actions to the Mac.

## Shared skills inside T3

Keep the shared skill's task, constraints and acceptance criteria. Replace
its Paseo execution mechanics with the following T3 mechanics. In particular,
Paseo profile discovery and terminal callbacks are not prerequisites in T3.

| Shared workflow | T3 execution |
| --- | --- |
| `paseo-advisor` | One read-only child with a self-contained question and recommendation request. |
| `paseo-committee` | Two read-only children with independent briefs; collect findings and resolve objections. |
| `code-review` | Separate Standards and Spec children, each given its sources and a fixed diff. |
| `paseo-handoff` | A self-contained child task; create a top-level thread only when the user requests a new thread. |
| `paseo-loop` | Unscheduled worker/verifier cycles use T3 children with explicit exit criteria and limits. Scheduled cycles stay in Paseo. |
| `babysit-pr` | The parent thread uses native PR watches; see below. |
| `label-and-implement-with-pr` | Claim, implement, verify, create and link the PR, then let the top-level thread watch it. |

Verify the selected provider and settings before launching a child. Use the
same provider as the parent unless the user explicitly requests another.
Paseo profile names and notes are not T3 model identifiers: translate the
requested role into a brief and use the available provider/model/options.
If a named profile cannot be resolved, report that rather than substituting
a different provider.

Use native same-provider children for work completed in this turn with
inherited settings. Use T3 `delegate_task` for a separate worktree, background
work or explicitly requested settings. Discover its capabilities before the
first delegation and follow the tool's completion instructions. Every new
review or re-check is a fresh task. Cancel work that is replaced or no longer
needed. A delegated child does its own work and creates no further children
unless its brief requests them.

For handoffs, include the objective, exact branch/head, edits and commits,
decisions, unsuccessful attempts, verification results, remaining blockers,
PR links and the user's constraints. A portable context transfer is not a
replacement for an explicit brief. Mention another T3 thread using its
returned link.

An unscheduled worker/verifier loop alternates implementation and independent
verification against the user's exit criteria, within an explicit iteration
and elapsed-time limit. Give each verifier the changed head and original
criteria. Report remaining failures when a limit is reached and cancel live
children when stopping. Use task completions to continue the cycle rather
than creating a recurring prompt.

Schedules, heartbeats and existing scheduled Paseo worker/verifier loops
continue to use Paseo. Do not recreate them as T3 scheduled tasks.

## Pull requests and supervision

Use the `babysit-pr` skill for failure classification, review responses,
rebasing and bounded reruns. In T3, the following replaces its watcher
terminal, callback wrapper and polling lifecycle:

1. Check the PR's scope against its base. Read existing review feedback and
   checks, and handle actionable items before watching.
2. After creating, taking over or pushing to a PR, call `link_pull_request`
   with its full URL as the next tool call. Link every layer of a stack.
3. The top-level thread calls `watch_pull_request` after any required branch
   update and push, then ends its turn. A child returns the PR URL, head SHA
   and check/review state; its parent owns the watch.
4. On a wake, read the current head and current feedback. Address reviews
   before retrying CI. Fetch and assess the base; update the branch when
   conflicts or required up-to-date checks need it. Preserve the skill's
   maximum of three infrastructure/flaky reruns per head SHA and report the
   count across wakes. The native watch remains active across pushes and
   wakes, so do not recreate it after each push.
5. Before a final handback or human blocker, call `unwatch_pull_request` and
   report the head SHA, check/review state and remaining work. A deliberate
   wait for the next watch event is not a final handback.

Native watches detect failed checks, passed required checks, new comments or
reviews, and conflicts. They do not establish full acceptance or authorize
merging. Verify the exact head and required CI coverage before reporting it
accepted. Green CI is a milestone while waiting for the reviewer to merge.

Comments from the GitHub account T3 uses do not wake the watch. If a human
decision is needed, ask in the T3 thread and explicitly hand back; the user
can resume the thread after answering. Stop, settlement and archival can end
watches. Check the watch state when resuming rather than assuming a stopped
thread is still supervising the PR. Use native watches instead of terminal
watchers, scheduled prompts or shell polling.

## Simulator verification

Record already-booted devices before runtime work and preserve them. Discover
devices with `device_list`, open the chosen host/device using `device_open`,
and use the returned `agent-device` command for app launches, interaction,
screenshots and recordings. Use `device_screenshot` to inspect the screen.
Builds, installs, logs and the project's XCUITest runners may still use Xcode
and simctl.

Shut down only simulators this task booted, including after failures. Closing
the Device panel alone leaves a simulator running. If none remain booted,
quit Simulator. The Device panel assists inspection; canonical iPhone
XCUITest remains the UI acceptance gate.

## Provider hooks

Keep the provider adapters in `.codex`, `.claude` and `.pi`. Codex normalizes
`exec_command` to `Bash` with `tool_input.command` for lifecycle hooks, so the
existing `^Bash$` matcher is intentional. The hook dispatcher can be exercised
with JSON input without executing the command being checked. Hook trust and
loading belong to the provider, not to T3 project actions.

## References

- [T3 host CLI](https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md#scripts-on-the-host)
- [PR watches](https://github.com/pingdotgg/t3code/blob/main/docs/user/source-control.md#linked-pull-requests)
- [Project settings](https://github.com/pingdotgg/t3code/blob/main/docs/user/project-settings.md)
- [Devices](https://github.com/pingdotgg/t3code/blob/main/docs/user/devices.md)
- [Codex hook tool coverage](https://learn.chatgpt.com/docs/hooks#tool-coverage)
