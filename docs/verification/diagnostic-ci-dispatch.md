# Diagnostic CI dispatch

The existing CI workflow accepts an optional boolean `diagnostic_only`, default
`false`. A dispatch with `true` selects only the existing diagnostic iPhone lane
and skips both Linux jobs. PR, push and default dispatch coverage is unchanged.
Dispatch concurrency uses a separate namespace from PR and push runs.

After publishing a frozen branch containing the intended source and workflow:

```sh
gh workflow run ci.yml --repo Julesseg/tsk --ref <frozen-branch> -f diagnostic_only=true
```

Verify the returned run's `headSha` matches that branch's intended commit before
using its results. Checkout uses that workflow ref; there is no source-ref input.
Diagnostic results supplement the full PR gate. Separate concurrency prevents
cancellation collisions, but simultaneous simulator jobs can still contend for
resources. Actual branch dispatch must be verified on GitHub.
