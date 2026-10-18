# Diagnostic CI dispatch

The CI workflow accepts an optional boolean `diagnostic_only`, default `false`.
A dispatch with `true` selects only the existing diagnostic iPhone lane and
skips both Linux jobs, overriding `ui_suite`. Otherwise manual dispatch defaults
to full coverage. PR and push use smoke coverage; the nightly schedule uses
full coverage. See [CI test tiers](ci-test-tiers.md) for selections and budgets.
Dispatch concurrency uses a separate namespace from PR, push and scheduled runs.

After publishing a frozen branch containing the intended source and workflow:

```sh
gh workflow run ci.yml --repo Julesseg/tsk --ref <frozen-branch> -f diagnostic_only=true
```

Verify the returned run's `headSha` matches that branch's intended commit before
using its results. Checkout uses that workflow ref; there is no source-ref input.
Diagnostic results supplement the selected PR gate. Separate concurrency prevents
cancellation collisions, but simultaneous simulator jobs can still contend for
resources. Actual branch dispatch must be verified on GitHub.
