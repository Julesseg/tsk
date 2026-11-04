# CI history diagnostic — 30 October 2026

The main problem is expensive, unreliable UI execution compounded by queueing and repeated work. The recent smoke reduction is useful, but the full suite still has no successful nightly in this history. There are also concrete orchestration defects that can report failure after tests succeed. Increasing timeouts or automatically retrying everything would increase cost without repairing those defects.

## Scope and accounting

Read-only GitHub audit of **all 20 PRs** and all **475 workflow runs** returned for 12–30 October 2026. The frozen listing ends at run `41137025903`, created 22:16:39 UTC on 30 October; two CI runs were active in that snapshot. Later executions are excluded. Inspected 270 CI runs, all 317 attempt records, all CI job records, all **341 distinct failed Mac-job logs**, 114 failed aggregation-gate logs, successful controls/timing samples, two retained simulator/transport artifacts, and current/historical repository sources. No workflows or tests were changed, no checks rerun, no simulator booted.

GitHub repeats retained jobs under new IDs on later attempts. Deduplication uses run ID, job name, start/end timestamps and runner identity. Cancelled jobs with no runner and no steps contribute **zero execution time**, even when their API start/end fields span hours. These corrections remove 168 duplicate CI job records and 33.2 hours of queued-only Mac records from naive totals. Distinct workflow runs at the same SHA remain distinct work. The final execution total below supersedes preliminary estimates during collection.

Observed job time is elapsed runner occupation, **not invoiced compute**. Workflow elapsed time uses each attempt's `run_started_at` to `updated_at` as an API-observed terminal-time approximation; queue delay is job `created_at` to actual `started_at` for assigned runners. Queue sums are not added to compute. Latest run conclusions, attempt conclusions, job conclusions and test results have different denominators.

Sources: [workflow runs API](https://docs.github.com/en/rest/actions/workflow-runs), [jobs and attempt API](https://docs.github.com/en/rest/actions/workflow-jobs), [Actions run history](https://github.com/Julesseg/tsk/actions/workflows/ci.yml). Read-only reproduction scripts, cached API responses, sanitized extracted metrics and an execution ledger are in `/tmp/tsk-ci-audit/`; the ledger is `executions.csv`, aggregate results `summary.json`, collectors `collect.py`/`fetch-details.py`/`fetch-gates.py`, parser `parse-logs.py`, analyzer `analyze.py`. Raw logs/artifacts stay outside the repository. Recollection updates the snapshot; analysis of the cached snapshot is repeatable.

## Extent

| Measure | Result |
| --- | ---: |
| CI workflow runs | 270 |
| Latest run outcomes | 38 success, 139 failure, 91 cancelled, 2 active |
| CI attempts, including reruns | 317; 315 completed |
| First-attempt outcomes | 27 success, 154 failure, 87 cancelled, 2 active |
| Distinct assigned, completed Mac executions | 593 |
| Observed Mac execution | **410.8 hours** |
| Successful Mac execution | 114 jobs / 54.3 hours |
| Failed Mac execution | 341 jobs / **290.1 hours** |
| Cancelled after runner assignment | 138 jobs / **66.4 hours** |
| Mac executions exceeding one hour | 109 / 593 |
| Actual Mac executions on attempts after the first | 64 / 40.0 hours |
| Separate Release workflow Mac occupation | 13.8 hours, excluded from CI total |

About **87% of CI Mac time ends in a failed or cancelled job**. That is not all recoverable waste: some failures identify real defects and continued execution gathers useful evidence. It does establish that the main cost is obtaining dependable feedback, rather than running the fast Core tests. Core jobs have no failures in this snapshot and median elapsed 1.27 minutes. Persistent Native jobs have seven failures and median 1.80 minutes. Neither is the source of hour-long PR latency.

| CI event | Completed attempts | Median elapsed | 90th percentile | Over 60 minutes | Mac hours |
| --- | ---: | ---: | ---: | ---: | ---: |
| PR | 207 | 34.5 min | 104.3 min | 41 | 222.1 |
| Manual dispatch, all selections combined | 79 | 46.7 min | 146.8 min | 28 | 138.3 |
| Main push | 17 | 29.9 min | 45.1 min | 1 | 10.3 |
| Nightly | 12 | 125.0 min | 141.7 min | 12 | 40.0 |

**All 12 nightly runs failed.** Only four of 79 completed manual attempts succeeded; manual includes focused diagnostics as well as full coverage. Do not read this as a full-suite pass rate. Across all events, the longest API-observed attempt lasted 288.9 minutes. The longest actual Mac job occupied a runner for 251.0 minutes; those historical limits predate today's configuration.

The seven Native failures are separate, early issues: three Clang/index-store configuration failures, one missing C compiler, one Swift concurrency compilation error, one persistence test with a missing file, and one Spotlight query-reader deadline/assertion failure. They occurred on 14–17 October. Examples: [missing compiler](https://github.com/Julesseg/tsk/actions/runs/38643603247/job/116125406803), [Swift compile failure](https://github.com/Julesseg/tsk/actions/runs/38899031142/job/116966416311), [query-reader failure](https://github.com/Julesseg/tsk/actions/runs/39073700614/job/117516383213). These are short build/test failures, not evidence that Core coverage should be cut.

## Where time goes

Deduplicated step time: **256.6 hours** in `Run prebuilt UI tests`, **106.0 hours** in the older combined `Build & run UI tests`, **16.1 hours** building the synchronization fixture/independent peer, and **8.3 hours** in explicit `Build UI test products`. The old combined step cannot be divided reliably into build and execution from step metadata. These two UI steps together account for **88%** of Mac occupation. Build caching is worthwhile but cannot explain or remove most of the recorded time.

In 282 failed Mac executions, logs contain a failed XCTest method. Another 59 failed without a completed failed UI method in the log; these include transport/setup failures, harness checks, build/fixture issues, artifact validation and interrupted XCTest. Absence of a completed failed method does not establish an infrastructure cause.

After the first completed failed UI method, those 282 jobs spent a further **171.5 hours** inside their UI step. Median remaining time was 17.7 minutes, with a 100.5-minute 90th percentile. This is a latency/evidence tradeoff, not a claim that all remaining tests should be discarded. A failing assertion stops its method, while later methods continue; Share failure exit 65 explicitly permits the rest of the suite to run. The 600-second XCTest allowance applies per method, not to the whole process. Synchronous accessibility snapshot calls can also outlast a helper's polling deadline. Sources: [execution wrapper](https://github.com/Julesseg/tsk/blob/5f38f3a/scripts/run-ui-tests.sh#L108-L164), [Apple per-test allowance](https://developer.apple.com/documentation/xctest/xctestcase/executiontimeallowance), [readiness collection](https://github.com/Julesseg/tsk/blob/5f38f3a/App/TskUITests/TaskControlReadiness.swift#L89-L129).

## Later smoke-era execution is shorter; queueing hides it

Current main already selects **4 iPhone + 2 iPad smoke methods**, versus 22+19 before consolidation, and excludes native keyboard transport setup from smoke. Full remains 71 iPhone / 62 iPad executions. Feature branches can select additional new tests. Do not propose the existing smoke reduction as future work. Sources: [selection](https://github.com/Julesseg/tsk/blob/5f38f3a/scripts/ui-test-selection.py#L7-L25), [consolidation record](https://github.com/Julesseg/tsk/blob/5f38f3a/docs/verification/test-suite-consolidation.md).

Calendar cohorts before/after the 28 October 15:15:10 UTC smoke/HID change, using completed first-attempt PRs:

| Measure | Earlier cohort | Later cohort |
| --- | ---: | ---: |
| PR attempts | 136 | 29 |
| Assigned Mac jobs | 272 | 51 |
| Median Mac job execution | 31.2 min | **19.5 min** |
| 90th percentile execution | 97.6 min | **26.0 min** |
| Median runner queue | 0.12 min | **18.1 min** |
| 90th percentile queue | 0.18 min | **97.2 min** |
| Median PR elapsed | 34.2 min | **44.4 min** |
| PR attempts exceeding one hour | 24 | 12 |

No assigned Mac job in the later first-attempt PR cohort ran for an hour. Its long end-to-end latency comes from waiting and orchestration, despite shorter execution. These are mixed historical cohorts with different sources, branches, outcomes and workloads, not a controlled causal benchmark.

Across the entire snapshot, 26 assigned Mac jobs waited over an hour; maximum 169 minutes. [Run 40964523636](https://github.com/Julesseg/tsk/actions/runs/40964523636) includes that 169-minute wait. PR smoke and manual runs on the same branch/SHA overlap in **52 first-attempt pairs**. Separate concurrency groups intentionally allow this. More shards or cancelling all cross-event work are not safe default answers: first measure runner supply, identify required acceptance coverage, and avoid replaying redundant builds/tests. Queueing alone does not reveal whether the cause is provider capacity, account limits or local workload. [Concurrency definition](https://github.com/Julesseg/tsk/blob/5f38f3a/.github/workflows/ci.yml#L29-L31), [official semantics](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

## Reliability: established causes versus unresolved symptoms

### False-red aggregation gates: confirmed

Five failed gate logs show `in_progress/None` after their expected shard had already reached a terminal state. **Two rejected a successful shard**:

- [Run 41050006887, gate 124090429904](https://github.com/Julesseg/tsk/actions/runs/41050006887/job/124090429904), attempt 2: iPhone completed successfully at 13:31:43 UTC; the gate rejected it as in progress at 13:31:49.
- [Run 41097235250, gate 124220266882](https://github.com/Julesseg/tsk/actions/runs/41097235250/job/124220266882): iPad completed successfully at 17:50:08 UTC; rejected as in progress at 17:50:14. Its iPhone independently failed, so repairing this gate alone would not make the overall workflow green.

The checker does one API read and immediately fails on nonterminal state. **Bounded polling for API convergence** can remove these false failures without replaying Mac tests. Preserve rejection of actual terminal failure/cancellation, duplicates and eventual missing results. [Checker](https://github.com/Julesseg/tsk/blob/5f38f3a/scripts/check-ui-shards.py#L6-L14), [caller](https://github.com/Julesseg/tsk/blob/5f38f3a/.github/workflows/ci.yml#L265-L273).

The hypothesis that partial reruns always lose earlier successful shards is false: GitHub materializes retained successes in the new attempt. For example, run 41082914123 presents iPad as new job IDs on attempts 1/2 with identical 15:41:20–16:07:30 execution timestamps. This behavior is why this audit deduplicates execution rather than summing API rows.

### Unchanged-source outcome changes: confirmed

With a strict comparison of **same run, same named lane, same method, different attempts**, **36 distinct methods** changed between pass and fail across 67 method/run/lane groups. This is evidence of nondeterministic outcomes, not proof that the assertion, app, simulator or external service is individually responsible. Three additional methods differed across parallel lanes, excluded from this stricter rerun count.

| Journey | Failed executions observed in inspected logs | Unchanged-source rerun groups with both outcomes |
| --- | ---: | ---: |
| Spotlight exact-task open and completion removal | 86 | 7 |
| Installed Share extension save/readback | 77 | 4 |
| Annotation editing and durable reopen | 60 | 5 |
| Independent native text/command recognition | 55 | 2 |
| Installed widget render/complete/deletion | 51 | 2 |
| Row save, validation, pickers and completion | 33 | 7 |

Failure counts are historical executions, not unique regressions or percentages. Successful timing/control logs are sampled and failure-heavy, so their pass counts are not a denominator for a population flake rate. The comparison holds source/ref and lane fixed; runner instances and service/runtime conditions can still vary. [GitHub rerun source identity](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).

Examples: [annotation run 39807222791](https://github.com/Julesseg/tsk/actions/runs/39807222791) fails on attempt 1 and passes on subsequent attempts; [row run 40919794083](https://github.com/Julesseg/tsk/actions/runs/40919794083) contains a passing row method on attempt 1 and failure on attempt 2. These are stronger evidence than comparing unrelated commits.

### Simulator/transport failures: confirmed examples, prevalence unresolved

Two retained artifacts were inspected beyond console logs:

- [Run 40708413564, iPad job 122886947480](https://github.com/Julesseg/tsk/actions/runs/40708413564/job/122886947480), artifact `12825927362`: owner receipt reports relay initialization exceeding its deadline; relay remains `preparing`, with zero cases/exchanges. No UI journey ran. This predates smoke's removal of keyboard transport.
- [Run 40419394715, iPad job 121909828425](https://github.com/Julesseg/tsk/actions/runs/40419394715/job/121909828425), artifact `12698505531`: simulator service logs show loss of SimLaunchHost at 23:42:37 UTC, companion reports the target offline at 23:42:44, and relay ends with `IdbConnectionException`. This supports simulator-host/transport loss; the initiating reason for the service loss remains unknown.

No GitHub runner-lost-communication signature was found in the 341 failed Mac console logs. That does not rule out platform incidents. It does mean **blanket attribution to GitHub infrastructure is unsupported**. Console scanning additionally found snapshot errors in 34 jobs and test-allowance exceedance markers in 20; those symptoms do not separate app layout loops from slow/dead simulator services. Root-cause prevalence requires more retained xcresult/host artifacts or controlled base/head runs. Do not label every exit 65/70 a flake or infrastructure failure.

### Build artifact failures reported late: confirmed

Four jobs passed their UI step then failed on missing App Intents metadata. They spent **68.5 minutes of UI execution** before this artifact-only failure was reported. Example [run 40964509788, job 123765669725](https://github.com/Julesseg/tsk/actions/runs/40964509788/job/123765669725). Move the existing verifier directly after build, before simulator creation. This preserves the check and avoids that execution on invalid products. It does not fix metadata generation itself. [Current verifier placement](https://github.com/Julesseg/tsk/blob/5f38f3a/.github/workflows/ci.yml#L228-L230).

## Growth and expensive journeys

| Source milestone | Declared UI methods | UI Swift lines including helpers |
| --- | ---: | ---: |
| PR #36, `d65ff0a` | 50 | 4,504 |
| PR #37, `c27a217` | 55 | 5,035 |
| PR #52, `83ff10c` | 60 | 5,285 |
| PR #59, `d3c14fe` | 64 | 5,506 |
| Before consolidation, `83d4e39` | 73 | 5,960 |
| Consolidation, `43d32ac` | 67 | 5,845 |
| Current main, `5f38f3a` | 71 | 6,133 |

Methods grew **42%** since PR #36; source grew 36%. Current runtime UI/keyboard/simulator/intent harness totals roughly 2,513 lines including sync fixture, plus 1,941 matching harness-regression lines. These are maintenance surface measurements, not proof that coverage is unnecessary. Source counts use `func test...` declarations and `git show`/`ls-tree` at the pinned commits.

No unconditional sleep calls were found in Swift UI tests. Static sites include 120 launches, 96 terminations and 598 conditional waits. Helpers and loops can multiply actual calls. Conditional waits return early; summing their configured maxima would be misleading. Normal fixture launch already disables app animations. Therefore profile launch, quiescence, typing and accessibility activities before proposing arbitrary wait deletion.

Historical successful-method timings from inspected logs, pooling versions/families (diagnostic sample, not a current benchmark):

| Journey | Successful observations | Median | 90th percentile |
| --- | ---: | ---: | ---: |
| All typed values, validation and persistent reopen | 52 | 7.10 min | 11.15 min |
| Typed saved-view edit/reopen | 53 | 5.78 min | 8.20 min |
| Installed Share extension | 112 | 5.12 min | 7.20 min |
| Reminder recurrence copy/history | 82 | 4.45 min | 6.43 min |
| Row durable edit journey | 34 | 4.41 min | 5.92 min |
| Series metadata preview/save/reopen | 77 | 4.16 min | 5.85 min |

Some historical runs predate today's 600-second test limit; pooled old outliers must not be used to claim that today's configuration permits a successful 88-minute method. Long methods need inspection for duplicated validation that belongs in Core, while retaining actual persistence, native input and system delivery assertions at the UI seam.

Full partitioning is measurably uneven, not merely uneven by method count:

| Partition | Assigned terminal jobs | Median job execution | Successful jobs |
| --- | ---: | ---: | ---: |
| iPhone workspace, 64 current methods | 20 | **115.1 min** | 1 |
| iPhone row editing, 7 current methods | 19 | **28.1 min** | 1 |
| iPad workspace, 55 current methods | 20 | **62.6 min** | 0 |
| iPad row editing, 7 current methods | 19 | **31.2 min** | 7 |

Historical selections and failures vary, and these include cancellations. They establish an expensive workspace tail, not a guaranteed fourfold speedup from rebalancing. Move towards measured thematic/duration-balanced partitions within actual runner capacity; preserve Share ordering, native keyboard ownership, fixture dependencies and exact coverage union.

## PR-by-PR cost

CI runs include PR and manual runs associated by GitHub PR metadata, falling back to exact head branch. Main/scheduled runs are excluded from this table; historical runs may not retain PR association. Attempts include partial reruns. Mac hours exclude retained copies and queued-only jobs. A merged PR or a green smoke run does not establish full-system acceptance.

| PR | State at snapshot | CI runs / attempts | Mac hours | Latest run outcomes: success / failure / cancelled / active |
| --- | --- | ---: | ---: | --- |
| [#1](https://github.com/Julesseg/tsk/pull/1) | merged | 1 / 1 | 0.0 | 1 / 0 / 0 / 0 |
| [#2](https://github.com/Julesseg/tsk/pull/2) | merged | 2 / 2 | 0.2 | 2 / 0 / 0 / 0 |
| [#36](https://github.com/Julesseg/tsk/pull/36) | merged | 53 / 55 | 118.7 | 1 / 29 / 23 / 0 |
| [#37](https://github.com/Julesseg/tsk/pull/37) | merged | 53 / 57 | 52.9 | 5 / 17 / 31 / 0 |
| [#38](https://github.com/Julesseg/tsk/pull/38) | merged | 1 / 3 | 2.4 | 1 / 0 / 0 / 0 |
| [#50](https://github.com/Julesseg/tsk/pull/50) | merged | 2 / 3 | 2.0 | 1 / 0 / 1 / 0 |
| [#51](https://github.com/Julesseg/tsk/pull/51) | closed | 1 / 1 | 0.0 | 1 / 0 / 0 / 0 |
| [#52](https://github.com/Julesseg/tsk/pull/52) | merged | 9 / 9 | 16.9 | 3 / 3 / 3 / 0 |
| [#54](https://github.com/Julesseg/tsk/pull/54) | merged | 1 / 1 | 0.0 | 1 / 0 / 0 / 0 |
| [#59](https://github.com/Julesseg/tsk/pull/59) | merged | 11 / 16 | 17.8 | 2 / 5 / 4 / 0 |
| [#60](https://github.com/Julesseg/tsk/pull/60) | open | 6 / 10 | 16.8 | 0 / 4 / 2 / 0 |
| [#61](https://github.com/Julesseg/tsk/pull/61) | merged | 23 / 30 | 28.6 | 1 / 18 / 4 / 0 |
| [#62](https://github.com/Julesseg/tsk/pull/62) | merged | 3 / 7 | 4.9 | 1 / 1 / 1 / 0 |
| [#63](https://github.com/Julesseg/tsk/pull/63) | merged | 2 / 6 | 4.5 | 0 / 2 / 0 / 0 |
| [#71](https://github.com/Julesseg/tsk/pull/71) | merged | 1 / 1 | 0.0 | 1 / 0 / 0 / 0 |
| [#72](https://github.com/Julesseg/tsk/pull/72) | merged | 4 / 7 | 17.4 | 2 / 2 / 0 / 0 |
| [#73](https://github.com/Julesseg/tsk/pull/73) | merged | 6 / 7 | 5.5 | 1 / 1 / 4 / 0 |
| [#74](https://github.com/Julesseg/tsk/pull/74) | open | 29 / 35 | 45.6 | 2 / 11 / 14 / 2 |
| [#75](https://github.com/Julesseg/tsk/pull/75) | open | 6 / 9 | 5.5 | 2 / 2 / 2 / 0 |
| [#76](https://github.com/Julesseg/tsk/pull/76) | merged | 4 / 5 | 6.4 | 1 / 3 / 0 / 0 |

## Recommended work, in order

1. **Repair gate API convergence first.** Poll only missing/nonterminal API state with backoff and a short bounded deadline; terminal failures remain failures. Add a stale-then-success checker regression and verify a gate-only refresh. Benefit: remove proven false reds; no speculative test deletion or additional Mac execution.
2. **Control duplicate demand and expose queue time.** Record source SHA, suite, family/partition, toolchain/runtime and reason for every dispatch. Reuse successful acceptance evidence only when all those execution identities match; avoid repeatedly dispatching full while a matching run is already active. The 52 overlapping same-SHA PR/manual pairs, 138.3 manual Mac hours and 66.4 cancelled Mac hours justify investigating demand before adding workers. Different coverage can be required, so overlap is not automatically redundant. Separate status polling from test reruns. Targeted same-SHA retries are supported; do not replay all jobs to refresh a gate.
3. **Fix the highest-impact unstable seams with frozen comparisons.** Start with Spotlight, row editing, Share and annotations. For each, run a small fixed-SHA focused sample and a base control on the same toolchain/family; capture xcresult activity timings, service lifetime and transport receipts. Keep assertions, operation deadlines and native-input ownership. The 36 outcome-changing methods are a triage list, not permission to suppress them. Surface first failure immediately; stop further execution only on proven device/transport unavailability, preserving useful independent tests after ordinary assertions.
4. **Rebalance full coverage and isolate system-sensitive work.** Use per-method duration and failure data, not counts alone, to redistribute the 115-minute phone workspace tail. Separate system services/native keyboard from ordinary task journeys where that yields reliable fault isolation. Keep current full coverage requirements for system integrations and behavior outside smoke. More workers only help when queue/capacity permits; run a controlled same-SHA comparison and measure both critical-path time and total Mac minutes.
5. **Move artifact validation before UI execution.** A small reorder would avoid the measured 68.5 minutes across four historical failures. Then diagnose missing metadata generation separately. Prediction: the same invalid artifact fails before any simulator starts.
6. **Skip unused fixture setup and share immutable builds.** iPad smoke and row-only workers build a sync server/peer they do not consume. Derive separate server/peer requirements from actual selections, including Spotlight and missed-notification consumers. Retain the host library for controller checks. Build arm64 simulator products once per exact SHA/toolchain/signing identity and distribute app, extensions, runner and xctestrun products. This removes duplicate builds, but adds a fan-out dependency and transfer cost; measure wall time as well as total minutes. Rust caching already exists; Swift/DerivedData caching does not.
7. **Make Release demand deliberate.** Release adds 13.8 Mac hours and runs independently on PR updates. If installables are unnecessary on every push, use an explicit request or run after fast checks. Its `apple` native build compiles device plus both simulator architectures for a device-only archive; add a device-only target. Preserve actual archive/provisioning verification when release evidence is required. [Release source](https://github.com/Julesseg/tsk/blob/5f38f3a/.github/workflows/release.yml), [native build targets](https://github.com/Julesseg/tsk/blob/5f38f3a/scripts/build-native.sh#L22-L28).

Suggested acceptance budgets are **targets for experiments**, not measured promises: ordinary smoke runner execution p90 below 15–20 minutes; queue p90 below 5 minutes; full critical path below 45–60 minutes; zero false-red gates; at most one evidence-backed infrastructure retry; a green scheduled full run on both families. Report initial verdict separately from eventual retry success. Stop an experiment that trades a shorter critical path for substantially more queueing or compute.

The next concrete change should be the gate convergence fix plus early artifact validation. In parallel operational work, stop launching duplicate full runs for the same source/selection and publish queue/execution/first-failure timing in job summaries. Then use controlled runtime evidence to address test behavior and full-suite partitioning. No CI implementation or GitHub mutation was performed as part of this diagnosis.
