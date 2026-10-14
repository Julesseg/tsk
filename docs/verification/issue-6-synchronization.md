# TaskChampion connection and manual synchronization

The app exposes Synchronization from the task toolbar. A connection uses the existing TaskChampion server URL, client UUID and encryption secret shared by the user's Taskwarrior clients. Save connection persists settings on the current device; Sync now separately verifies server access and exchanges tasks. Editing settings requires saving before synchronizing. Disconnect removes connection settings and retains all locally saved tasks.

All task exchange runs through Core's `TaskManager.synchronize(using:)` and the pinned TaskChampion 3.1.0 native adapter. Upstream handles encrypted synchronization, operation merging and UUID identity. Native failures are shown without acknowledging server success or removing saved local work. Connection settings are separate from task attributes; the configuration file is atomic, has mode 0600, and uses file protection until first authentication on iOS.

## Verified locally

- Core suite: 5 tests passed. Failed synchronization retains the exact previously saved task and unknown attributes.
- Native suite: 7 tests passed with the real server and pinned Taskwarrior enabled. Connection settings, including the exact encryption secret, survive a new configuration-store instance; disconnect removes settings.
- Native failure: an actual connection refusal at an isolated localhost endpoint returns TaskChampion's synchronization error and preserves the previously committed task.
- Real encrypted interoperability: TaskChampion 3.1.0, Taskwarrior 3.5.0 and taskchampion-sync-server 0.7.1 exchanged tasks through an isolated localhost server. A native-created task reached desktop with the same UUID and opaque attribute; a desktop edit returned to native preserving annotations and opaque fields. A desktop-created task reached native with the same UUID and project. Repeating sync produced one record per tested identity. A wrong encryption secret failed while retaining a new local task.

The reusable native interoperability test is `realEncryptedTaskwarriorSyncConvergesBothWaysAndRetainsOpaqueFields`. Enable it using `TSK_TASKWARRIOR_BINARY`, `TSK_SYNC_TEST_URL`, `TSK_SYNC_TEST_CLIENT_ID`, and `TSK_SYNC_TEST_SECRET`; use a disposable server/client namespace and isolated local task directories. It asserts the Taskwarrior version is 3.5.0. The ordinary native suite still exercises genuine unavailable-server failures without an external fixture.

## UI verification

`SynchronizationUITests` covers connection validation, persistence across app relaunch, genuine unavailable-server failure, retaining offline work, retry and disconnect. A successful native UI sync scenario uses a real isolated server when the test runner receives `TSK_UI_SYNC_SERVER_URL`, `TSK_UI_SYNC_CLIENT_ID`, and `TSK_UI_SYNC_SECRET`; it explicitly skips without that fixture.

Local simulator execution and screenshots were blocked by machine disk exhaustion; no simulator was booted for this ticket. CI is the canonical XCUITest gate. The pinned Rust bridge compiled for arm64 iOS Simulator; `xcodebuild build-for-testing` succeeded for the app and XCUITest targets using the generic iOS Simulator destination with `ARCHS=arm64`. Compilation does not prove execution. The local UI report lists each missing screenshot rather than presenting simulated captures.

No personal server or Taskwarrior configuration was accessed or changed. Signed-device provisioning, personal account/server connectivity, physical-device behavior and background scheduling remain unverified. Automatic foreground/background synchronization belongs to subsequent slices.
