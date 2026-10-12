# Auto-dispatch: ready issues to Paseo agent sessions

Issues marked `ready-for-agent` are implemented automatically after their
blockers close. Paseo starts a configured agent provider on a self-hosted Mac
runner and keeps the session visible in its desktop and mobile apps.

## How it works

1. `unblock-dispatch.yml` scans open `ready-for-agent` issues when an issue is
   completed or the workflow is run manually. It parses `- #N` bullets under
   `## Blocked by`, skips umbrella issues, and dispatches work that is ready.
2. `agent-implement.yml` re-checks the issue, validates the configured Paseo
   provider and model, fetches the checkout, and starts a background worktree
   session on `agent/issue-<N>`.

The instruction tells the selected agent to use the
`label-and-implement-with-pr` skill. Install that skill and its `implement`,
`ui-report`, and `babysit-pr` dependencies under `~/.agents/skills` on the
runner. Client-specific skill directories are compatibility adapters, not the
source of truth.

## Scope rules

- Only issues labeled `ready-for-agent` are selected automatically.
- An issue is ready when its `## Blocked by` list is empty or all listed issues
  are closed.
- Titles beginning `[Epic]` or `Spec:` are skipped.
- The agent applies `agent-dispatched` after it starts. The dispatcher does not
  claim work before a session exists.

## Paseo configuration

Set these repository Actions variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `PASEO_PROJECT_DIR` | yes | none | Checkout path on the runner |
| `PASEO_PROVIDER` | yes | none | Provider passed to `paseo run` |
| `PASEO_MODEL` | yes | none | Model passed to `paseo run` |
| `PASEO_THINKING` | no | unset | Optional reasoning option |
| `PASEO_MODE` | no | unset | Optional provider permission mode |
| `PASEO_BASE` | no | `origin/main` | Ref used to create the worktree branch |

There are no provider, model, thinking, or permission-mode defaults. The
workflow validates the provider status, authentication, model, and optional
thinking value before it fetches or creates a branch. Inspect valid values with:

```sh
paseo provider ls
paseo provider models <provider> --thinking
paseo provider diagnostic <provider>
```

The resulting command has this shape:

```sh
paseo run --background \
  --provider <provider> \
  --model <model> \
  --cwd <checkout> \
  --new-workspace worktree \
  --worktree-mode branch-off \
  --new-branch agent/issue-<N> \
  --base origin/main \
  "Use the label-and-implement-with-pr skill to implement issue #<N>."
```

Optional `--thinking` and `--mode` arguments are added only when configured.

## One-time Mac setup

1. Register a macOS self-hosted runner and install it as a service.
2. Start Paseo at login and confirm `paseo ls` works for the runner account.
3. Set `PASEO_PROJECT_DIR`, `PASEO_PROVIDER`, and `PASEO_MODEL`. Ensure the
   checkout's `origin` is reachable unattended.
4. Authenticate `gh` and the selected Paseo provider for the same account.

Run `unblock-dispatch.yml` manually to rescan eligible issues. Run
`agent-implement.yml` with an issue number to bypass automatic scope rules;
the spawn-time issue re-check still applies unless `force` is selected.
