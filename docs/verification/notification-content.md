# Notification content and Time Sensitive delivery

Due alerts use the task title with an empty body. Planned alerts retain `Planned work`; combined alerts retain `Planned and due`. Immediate missed alerts use the same content as their scheduled counterparts, without the `(missed while away)` suffix.

Both submission paths set the native Time Sensitive interruption level. App, Share and Widget entitlements declare the capability because the common participant can schedule alerts from each process. User notification and Focus settings still control interruption. Distribution provisioning must authorize the capability for each target; no distribution archive or physical-device delivery was verified here.

On reconciliation, existing future registrations with stale text or interruption level are replaced using their original identifiers. Original event identity and acceptance timestamps remain intact. Delivered missed-alert evidence still decodes even when it has old content, so changing presentation does not cause a missed event to be submitted again. Already-delivered notifications are not rewritten.

## Verification

- `swift test --package-path Core`: 162 tests passed, including replacement of stale registrations and retention of acceptance identity/timestamps with no repeated registration after refresh.
- `swift test --package-path Native --filter nativeTaskAlertsUseCleanTimeSensitiveContentAndRecognizeLegacyRegistrations`: passed on macOS using native `UNMutableNotificationContent` and `UNNotificationRequest` objects, without reading or writing the host notification center. Covers all three kinds, scheduled/missed identifiers, title, body, sound, payload, interruption level, and legacy content readback.
- `xcodebuild build-for-testing` for generic arm64 iOS Simulator: succeeded. This compiles the app, extensions and UI test products; it does not establish delivery or appearance. The unchanged bridge artifact was reused after verifying matching `Native/Bridge` Git tree IDs.
- App, Share and Widget entitlement plists validate with Time Sensitive enabled.
- Local XCUITest, iPhone/iPad system notification screenshots, physical-device Focus behavior and distribution provisioning were not exercised. PR CI supplies canonical smoke coverage.

The local single-file UI report lists each missing before/after capture at `~/.local/share/ui-reports/tsk/clean-up-due-notifications-time-sensitive/report.html` (5,574 bytes). No browser was available for its phone-width rendering check.

Official contracts: [Time Sensitive interruption](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive), [Time Sensitive authorization uses the entitlement](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/timesensitive).
