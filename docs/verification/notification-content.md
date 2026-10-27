# Notification content and Time Sensitive delivery

Due alerts use the task title with an empty body. Planned alerts retain `Planned work`; combined alerts retain `Planned and due`. Immediate missed alerts use the same content as their scheduled counterparts, without the `(missed while away)` suffix.

Both submission paths set the native Time Sensitive interruption level. The app entitlement declares the capability. Share and Widget targets retain their existing App Group entitlements; Xcode lists Time Sensitive support for application and WatchKit extension product types, not these extensions. User notification and Focus settings still control interruption. The app distribution profile must authorize the capability; physical-device delivery remains unverified.

On reconciliation, existing future registrations with stale text or interruption level are replaced using their original identifiers. Original event identity and acceptance timestamps remain intact. Delivered missed-alert evidence still decodes even when it has old content, so changing presentation does not cause a missed event to be submitted again. Already-delivered notifications are not rewritten.

## Verification

- `swift test --package-path Core`: 162 tests passed, including replacement of stale registrations and retention of acceptance identity/timestamps with no repeated registration after refresh.
- `swift test --package-path Native --filter nativeTaskAlertsUseCleanTimeSensitiveContentAndRecognizeLegacyRegistrations`: passed on macOS using native `UNMutableNotificationContent` and `UNNotificationRequest` objects, without reading or writing the host notification center. Covers all three kinds, scheduled/missed identifiers, title, body, sound, payload, interruption level, and legacy content readback.
- `xcodebuild build-for-testing` for generic arm64 iOS Simulator: succeeded. This compiles the app, extensions and UI test products; it does not establish delivery or appearance. The unchanged bridge artifact was reused after verifying matching `Native/Bridge` Git tree IDs.
- App entitlement enables Time Sensitive; Share and Widget entitlement plists retain their existing App Group declarations.
- Local focused system UI checks are described below. iPhone/iPad notification screenshots and physical-device Focus behavior remain unverified. The signed IPA build and deployment passed on `9f7b168` after the app profile update; canonical CI for the runtime-selection correction remains pending.
- The first signed release failed: the existing app Ad Hoc profile lacks Time Sensitive. Xcode also rejected the original extension declarations, which were removed after checking `DVTPortalCachedPortalCapabilities.json` supported product types. The owner enabled the app capability, regenerated its Ad Hoc profile and updated `APPLE_PROVISIONING_PROFILE`; the signed release then passed. Share/Widget profiles and the distribution certificate remain unchanged.

The local single-file UI report lists each missing before/after capture at `~/.local/share/ui-reports/tsk/clean-up-due-notifications-time-sensitive/report.html` (5,574 bytes). No browser was available for its phone-width rendering check.

Official contracts: [Time Sensitive interruption](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive), [Time Sensitive authorization uses the entitlement](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/timesensitive).

## iPhone CI simulator selection

The failed `9f7b168` iPhone job selected iPhone Duo / iOS 27.1 even though the workflow selected Xcode 27.0. Its inline selector took the newest installed runtime before considering device preferences. The installed 27.1 runtime supports only Duo, so adding that runtime displaced the intended iOS 27.0 phone configuration. The iPad lane remained on iOS 27.0 and passed.

The selection regression reproduces this from mixed 27.0/27.1 inventory without booting a simulator. The five regressions failed against the original selector and pass with SDK major/minor matching. Coverage includes both device families, unavailable/non-iOS candidates, numeric patch ordering, missing matching families and the actual create/output boundary. The helper retains the existing device preferences, creates one owned simulator, and records its ID for the existing cleanup. The selector fix changes no test selection, assertion, deadline, keyboard transport or retry behavior.

A local run of the unchanged independent native keyboard case with the same prebuilt app reproduced the exact Duo failure: after typing `n`, `firstResponder=true`, `textLength=0`. On iPhone 18 Pro Max / iOS 27.0, plain `n` and Command-N passed; the direct XCTest Command-Return fallback failed later. With the existing CI-owned HID transport, the complete unchanged native keyboard case passed, including Command-Return. The original Spotlight membership/open/completion case and Widget rendering/completion/saved-view/deletion case also passed on this runtime. These comparisons used local Xcode 27.1; they demonstrate sensitivity to the selected device/runtime, not a complete hosted-toolchain comparison.

Local result bundles are under `.build/pr62-diagnosis/`: `duo-native-baseline.xcresult` and `stable-native-control.xcresult`. The original failed job is [122470767160](https://github.com/Julesseg/tsk/actions/runs/40545279343/job/122470767160). Canonical iPhone/iPad CI remains the acceptance gate for the runtime-selection fix.

The same local run exposed a separate Share reveal bug: the `dismiss-share-keyboard` bar covered the tag field at y=889 while the generic form frame still included that area. The failure recording shows Project retained focus and Tags underneath the bar. The two organization-field reveal calls now pass that existing bar as the lower inset to the existing helper. A later deadline tap at y=904.7 was intercepted by the same bar while XCTest reported no software keyboard. The date helper now dismisses editing whenever its existing dismissal button is present, including hardware-keyboard input. Existing geometry proofs cover the obstruction rule; no gesture fallback, retry, timeout extension or assertion change is introduced. The original full Share scenario is the runtime regression check.
