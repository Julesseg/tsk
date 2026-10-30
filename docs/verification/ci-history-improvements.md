# CI history improvements

Baseline: main `5f38f3a`. The [historical audit](../research/ci-history-2026-10-30.md)
contains the frozen run ledger and distinguishes queueing, execution, cancellation,
unchanged-source outcome changes and known infrastructure symptoms.

## Implemented changes

- Family gates poll missing/nonterminal GitHub API results for at most 90 seconds;
  duplicates and terminal failures remain red. A synthetic replay of the old
  checker reproduces the stale-state false red. New tests cover convergence,
  deadline expiry and terminal-failure precedence.
- One shared producer builds signed UI products and selected synchronization
  tools, and validates intent metadata/entitlements before creating simulators.
  Consumers verify checksum, source, SDK/toolchain/runtime and signatures.
- Full coverage remains four execution workers with every previous method once
  per family. Historical successful-median weights balance iPhone at 66/65 minutes
  and iPad at 72/68 before setup. Partitioning alone cannot promise sub-hour full
  execution; improved snapshot/layout behavior must be measured separately.
- Selection determines server, independent peer and native keyboard requirements.
  Task workers and iPad smoke no longer build/start unused fixtures. Core/Native
  Linux builds gain toolchain-specific Swift caches; Rust caches remain.
- Dispatch requires a named suite/reason and checks matching active work.
  Completed evidence reuse additionally requires the exact execution identity.
  Manual runs preserve in-flight evidence rather than cancelling it. Direct form
  requests and simultaneous-client races remain visible operational limits.
- Installable PR builds are explicit requests. Signing admission happens on Linux
  before claiming a Mac. Archives build only the device Rust target, including
  the existing App Store lane. Archive/provisioning acceptance still requires an
  actual requested release; simulator results cannot substitute for it.
- Worker and gate summaries distinguish method durations, first failure, queue
  and runner occupation. A nonblocking owned-device monitor stops execution only
  after a positively observed shutdown; inconclusive probes do not fail tests.

## Targeted instability experiments

Two title/header geometry transforms normalize equivalent heights to display
pixels before SwiftUI compares them. This addresses the previously observed
subpixel feedback mechanism without importing the separate `fixedSize` or
supporting-information changes from the issue #43 branch. Existing geometry,
large-text, completion and durable-edit assertions remain.

Run `41022221277`, iPad job `123952080434`, source `8d38e65a`, captured a native
Select All menu that was visible/enabled even though its accessibility lookup
consumed 5.64 seconds and failed the unchanged five-second deadline. Selection
now finds both supported native control types in one app snapshot, validates
unique enabled/contained geometry and performs one native tap. Actual clearing
and final value assertions remain; no Command-A fallback or model mutation was
introduced.

Run `40976426566`, iPad job `123805621484`, source `4ad146b7`, recorded a 63.98-second
keyboard snapshot after a full application snapshot had already returned. Keyboard
geometry now comes from that same captured application hierarchy; missing geometry
still fails, and the 20-second deadline and two stable samples remain.

Recent inspected annotations and two Spotlight journeys were passing. Their
ownership protocol, exact native-input assertions and system-delivery checks
remain. A residual Spotlight UUID reveal failure is distinct from indexing and
is unresolved until a current controlled run exercises it; no blind index-wait
increase was made.

## Evidence and acceptance

Local Core: 180 tests passed. Portable routing/selection/shard, build-transfer,
fixture admission, monitor cleanup, native transport and provisioning regressions
passed. Workflow syntax passed actionlint with the repository's custom runner
label declared. Modified Swift files passed syntax parsing. No local simulator
was booted. These checks establish portable behavior and syntax only.

Canonical evidence must include the actual shared build, smoke gates and full
coverage on both families at the PR head. Record their run links and method/job
measurements after completion. Product-transfer tests use temporary synthetic
products; they do not establish an actual signed iOS runner can launch transferred
bundles. Likewise, source-level release checks do not establish signed archive,
profile or physical-device acceptance.
