# Auto-dispatch: ready issues to T3 Code threads

Issues marked `ready-for-agent` are dispatched after their blockers close.
The self-hosted Mac runner starts a top-level T3 Code thread in an isolated
worktree. Paseo schedules and heartbeats continue to run in Paseo.

## How it works

1. `unblock-dispatch.yml` scans open `ready-for-agent` issues when an issue is
   completed or the workflow is run manually. It parses `- #N` bullets under
   `## Blocked by`, skips titles beginning `[Epic]` or `Spec:`, and selects
   issues with no blockers or only closed blockers.
2. The dispatcher serializes scans and caps in-flight work at three issues.
   Queued/running spawn jobs and a 30-minute successful-spawn grace period
   prevent duplicate dispatch until the agent claims its issue.
3. `agent-implement.yml` re-checks whether the issue is closed or claimed.
   `scripts/start-agent-thread.py` validates configuration, checks the running
   T3 server and registered project, fetches origin, then starts a thread on
   `agent/issue-<N>`, based on `origin/main` by default.
4. The thread uses the `label-and-implement-with-pr` skill. Its first action
   applies `agent-dispatched`; the dispatcher never claims work before a
   session starts. The thread implements, verifies, opens and links a PR,
   then supervises it using the native T3 watch.

The launcher returns after thread creation; GitHub Actions success is a
launch receipt, not evidence that implementation or CI passed. A launch
failure must be investigated before retrying: check for an existing thread,
branch and claim, including after an uncertain CLI/network result.

## Runner configuration

Set these repository Actions variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `T3_PROJECT_DIR` | yes | none | Absolute path of the registered checkout on the runner |
| `T3_BASE` | no | `origin/main` | Ref used for the new worktree |
| `T3_CLI` | no | PATH, then `~/.t3/bin/t3` | CLI executable path |
| `T3_BASE_DIR` | no | CLI default | T3 home when the server uses a custom data directory |

The workflow adds `~/.t3/bin` to PATH for the runner's minimal environment.
There is no dependency on the Paseo CLI, `PASEO_*` variables or a public T3
Connect tunnel. The local CLI connects to the server under the runner user.
The project must already be registered; the launcher creates no project.

Explicitly save the project's provider, model, reasoning options and default
permission mode in T3 before unattended dispatch. The launcher uses that
selection without provider/model overrides, preserving its reasoning options.
T3 0.1.5's `thread start` has no reasoning or permission-mode flags. Existing
Paseo settings are not silently translated. Check enabled provider instances
and models in T3's settings or with `orchestrator_capabilities` from a T3 agent.

## One-time setup and verification

1. Register a self-hosted macOS GitHub Actions runner. Run it as the same
   user as the T3 server, Git checkout and authenticated provider.
2. Register the existing checkout in T3 once and keep the server running.
   Install its background service if unattended availability is needed.
3. Install the shared `label-and-implement-with-pr`, `implement`, `ui-report`
   and `babysit-pr` skills under `~/.agents/skills`. This repository's
   [T3 adapter](t3-code.md) supplies their T3 mechanics.
4. Set the required variables, authenticate `gh` and the provider, and
   confirm the checkout can `git fetch origin` unattended.
5. Check connectivity without starting an agent:

   ```sh
   ~/.t3/bin/t3 thread list --project /absolute/path/to/tsk --json
   ```

6. After the migrated workflow reaches the default branch, dispatch
   `agent-implement.yml` for a real issue intended for implementation.
   Confirm its T3 thread, isolated branch, issue claim, linked PR and native
   PR watch. This is the end-to-end acceptance check; mocked launcher tests
   alone do not establish unattended delivery.

Run `unblock-dispatch.yml` manually to rescan eligible issues.
`agent-implement.yml` accepts an explicit issue outside automatic scope rules;
its closed/claimed re-check still applies unless `force` is selected. Giving
up removes the claim and explains why; a PR awaiting review retains it.

The launcher's regression tests run in the existing CI routing job. They
exercise argument safety, readiness checks, fetch failures and explicit
worktree creation without starting real agents.
