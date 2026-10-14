# Automatic synchronization and durable local priority

Core `TaskManager` owns synchronization configuration, status updates, single-flight attempts and queued retry work. Successful durable creation, editing and completion schedule synchronization without awaiting network completion. Failed local commits do not acknowledge a task or schedule an attempt. App opening, restored connectivity, background opportunities and manual retry reuse this policy. Device connection settings are loaded through the native session factory for other entry points.

The app observes Core status without querying SQLite to poll progress. Its task footer distinguishes local-only work, pending work, synchronization, verified server success and genuine failures with retry. A Network.framework path monitor requests reconciliation on an unavailable-to-available transition. Foreground activation also reconciles. The BGAppRefresh registration, permitted identifier and `fetch` mode provide opportunistic background execution; expiration cancels the attempt and retains local work. Scheduling/registration failures remain visible without disabling task use. No exact background timing is promised.

## Why detached execution also needs cancellation

Pinned TaskChampion 3.1.0 synchronization holds its SQLite `BEGIN IMMEDIATE` transaction across awaited server requests. Its public read-only storage mode still uses the same immediate-transaction path. Moving the synchronous FFI call to a detached task alone would keep local operations waiting behind the SQLite write lock.

The native adapter retains one TaskChampion dataset and its upstream synchronization/merge protocol. Sync runs detached. Path-specific native admission gives local operations priority: a local read/write interrupts the in-flight sync future, releasing its transaction, and a new sync waits for admitted local work to drain. Cancellation generations also invalidate requests canceled before their native execution starts. Core treats this interruption as pending work and coalesces the next attempt. Genuine network/server failures remain failures.

Admission and cancellation are process-local. They are **not** filesystem-shared coordination. App/widget/share process concurrency requires the separate shared-storage slice and real multi-process barrier verification; a Rust static registry does not prove that behavior.

## Actual verification

The reproducible native test uses an isolated HTTP proxy forwarding to taskchampion-sync-server 0.7.1. It holds replies until a test-controlled release file exists. It tests both a blocked GET and a POST already accepted by the real server before its client receives the reply or commits local sync state.

The original synchronous adapter failed all six capture/edit/completion barrier assertions. The new adapter acknowledged each durable operation while the reply remained held. After release and retry, an independent real TaskChampion replica received exactly one record per tested UUID, preserved opaque attributes, and retained the final completed state. This verifies cancellation/replay through upstream semantics rather than a substitute merge protocol.

Integrated checks passed: Core25 tests, Native18 tests with real server/pinned Taskwarrior fixtures, and arm64 app/XCUITest build-for-testing. The barrier also verifies a second actor accessing the same canonical storage path; this remains same-process evidence.

Further actual tests exercise a real HTTP 503 outage, successful local capture during failure, recovery after the connectivity trigger, and reopening a native session with persisted configuration. Existing pinned Taskwarrior 3.5.0 two-way encrypted synchronization checks remain enabled alongside these tests. All fixture data/configuration is isolated from personal accounts.

Tests: `durableNativeMutationsFinishWhileRealServerResponsesRemainBlocked`, `automaticSynchronizationRecoversAfterRealServerFailureAndConnectivitySignal`, `reopenedNativeSessionLoadsConfigurationAndUsesCommonAutomaticPolicy`, and Core single-flight/coalescing/failed-commit tests. Enable native network tests with `TSK_SYNC_TEST_URL`, `TSK_SYNC_TEST_CLIENT_ID`, and `TSK_SYNC_TEST_SECRET`; pinned Taskwarrior checks additionally use `TSK_TASKWARRIOR_BINARY`. The controlled proxy uses Python 3.

## Platform verification limits

The app and XCUITest targets compile for arm64 iOS Simulator, and built Info.plist readback verifies the actual background identifier and modes. Local simulator execution and screenshots remain blocked by disk-resource constraints; no simulator was booted for this ticket. Canonical CI runs the automatic-failure/capture/relaunch/retry UI scenario and produces screenshots.

Actual Network.framework restoration callbacks, BGTaskScheduler launch/expiration on a device, suspended-app execution frequency, physical-device behavior, signed provisioning and personal server connectivity remain unverified. Native build scripts set the iOS deployment target to the app's minimum 26.0 so crypto objects are not implicitly built for the newer local SDK.
