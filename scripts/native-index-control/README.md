# Independent native index control

This supplemental diagnostic builds a separate UIKit app with no tsk, TaskChampion,
sync, App Group or account dependency. It does not replace the original Spotlight
API, system Search, deep-link or canonical UI acceptance tests.

Dispatch the existing `ci.yml` with `native_index_control=true` and
`diagnostic_only=false`, after review and publication of this branch. Its separate
concurrency namespace cannot cancel the normal or diagnostic UI runs. Conflicting
inputs fail before any simulator work. Normal push, PR and diagnostic selections
remain unchanged.

One hosted Mac uses its selected latest-stable Xcode and an already installed
iPhone runtime. It builds and ad-hoc signs the standalone app once, then creates,
runs and cleans four fresh simulators **sequentially**:

| Named initializer | First operation |
| --- | --- |
| Explicit `completeUntilFirstUserAuthentication` | Delete owned domain |
| Explicit `completeUntilFirstUserAuthentication` | Index owned item |
| `CSSearchableIndex(name:)`, default protection | Delete owned domain |
| `CSSearchableIndex(name:)`, default protection | Index owned item |

The default-protection cases still use a named index; none uses
`CSSearchableIndex.default()`. Each process retains its index and queries for its
lifetime. Both orders index one synthetic item, query that exact identity, delete
only its UUID domain, and query empty. A delete-first case first deletes its empty
owned domain. The next operation starts only after the real previous callback.
There is no native retry, polling query, forced completion or service launch.

The observation ceiling is 120 monotonic seconds per cell after launch begins.
An outstanding operation remains `pending`, not an API error. A callback error
records only its domain/code; a successful callback with unexpected query results
is `query-mismatch`. Both are distinct from setup/command failures. Any incomplete
native cell makes the job nonzero but permits the next fresh cell. Setup or cleanup
failure stops the remaining cells. Signals preserve 130/143, other child failures
preserve their code, and command timeout is 124.

`result.json` and bounded per-cell receipts retain actual protection/index
availability, synthetic bundle/index/domain/item identity, PID, submit/return/
callback timestamps, query counts, exact-identity booleans and cleanup statuses.
A retained main-actor task records a heartbeat after each five-second sleep, at
most 24 times, through the same recorder. The exact typed ordinal and native
uptime show only that the main actor executed at those instants; absent events
do not prove process death. It makes no native index calls and never changes a
pipeline outcome. A failed heartbeat write stops only that task.

The host records actual receipt-observation start/end epochs and monotonic
elapsed time, separately from elapsed time since launch began. Both retain the
same launch-inclusive 120-second ceiling; a failed launch has no pretend
observation span. Compare native submit and heartbeat uptimes within their own
process; do not subtract them from host clock values.

Events are capped at 64 per cell and files at 64 KiB. The recorder encodes and
atomically writes a bounded candidate before committing it; a failure retains
the last valid receipt and emits a fixed write-failure marker. An unpublished
terminal outcome cannot turn a prior pending or missing receipt into success.
The reader permits only the known heartbeat shape and ordered ordinals, rejects
intervals shorter than five seconds beyond floating-point tolerance, and retains
longer intervals as actual scheduling observations. Tooling output is capped at
1 MiB per command. Stdout emits a small fixed-field summary. There are no
screenshots, videos, xcresults, provider content or error descriptions. Signature
details, source/executable hashes and actual toolchain/SDK/architecture are retained.

The runner records pre-existing booted devices and only shuts down/deletes its own
UUID. If creation fails after a side effect, it attempts recovery using the exact
random name it supplied, never a general device-name match. Every cleanup stage
is attempted even if another fails; Simulator quits only when none remain booted.
The runner owns/reaps its command process groups on timeout or signal. Forced
runner/host termination may prevent cleanup, and a failed recovery remains unknown
in the receipt. Ending a pending cell destroys the owned simulator; it does not
pretend that the outstanding native operation completed or was API-canceled.

Local verification is compile/sign only, with no simulator or Core Spotlight call:

```sh
python3 scripts/native-index-control/test_runner.py
python3 scripts/native-index-control/runner.py --build-only --output /tmp/unique-control-build
```

Availability and protected-data state do not guarantee callbacks. Apple documents
delete/index completion as journal acknowledgment, not necessarily applied index
visibility. A query mismatch is a real observation, not proof the API failed.
Fresh processes/devices reduce carryover but still share hosted Mac/runtime/service
conditions; comparison does not establish protection/order as the cause. Ad-hoc
identity and the minimal UIKit lifecycle differ from the production app. A control
pass cannot close its original pending callback, system Search or UI failures.

Primary contracts: [named index](https://developer.apple.com/documentation/corespotlight/cssearchableindex/init(name:)),
[explicit protection](https://developer.apple.com/documentation/corespotlight/cssearchableindex/init(name:protectionclass:)),
[protected data](https://developer.apple.com/documentation/uikit/uiapplication/isprotecteddataavailable),
[index availability](https://developer.apple.com/documentation/corespotlight/cssearchableindex/isindexingavailable()),
[delete completion](https://developer.apple.com/documentation/corespotlight/cssearchableindex/deletesearchableitems(withdomainidentifiers:completionhandler:)),
[index completion](https://developer.apple.com/documentation/corespotlight/cssearchableindex/indexsearchableitems(_:completionhandler:)).
