# Notification content and Time Sensitive delivery

Due alerts use the task title with an empty body. Planned alerts retain `Planned work`; combined alerts retain `Planned and due`. Immediate missed alerts use the same content as their scheduled counterparts, without the `(missed while away)` suffix.

Both submission paths set the native Time Sensitive interruption level. The app entitlement declares the capability. Share and Widget targets retain their existing App Group entitlements; Xcode lists Time Sensitive support for application and WatchKit extension product types, not these extensions. User notification and Focus settings still control interruption. The app distribution profile must authorize the capability; physical-device delivery remains unverified.

On reconciliation, existing future registrations with stale text or interruption level are replaced using their original identifiers. Original event identity and acceptance timestamps remain intact. Delivered missed-alert evidence still decodes even when it has old content, so changing presentation does not cause a missed event to be submitted again. Already-delivered notifications are not rewritten.

## Verification

- `swift test --package-path Core`: 162 tests passed, including replacement of stale registrations and retention of acceptance identity/timestamps with no repeated registration after refresh.
- `swift test --package-path Native --filter nativeTaskAlertsUseCleanTimeSensitiveContentAndRecognizeLegacyRegistrations`: passed on macOS using native `UNMutableNotificationContent` and `UNNotificationRequest` objects, without reading or writing the host notification center. Covers all three kinds, scheduled/missed identifiers, title, body, sound, payload, interruption level, and legacy content readback.
- `xcodebuild build-for-testing` for generic arm64 iOS Simulator: succeeded. This compiles the app, extensions and UI test products; it does not establish delivery or appearance. The unchanged bridge artifact was reused after verifying matching `Native/Bridge` Git tree IDs.
- App entitlement enables Time Sensitive; Share and Widget entitlement plists retain their existing App Group declarations.
- Local XCUITest, iPhone/iPad system notification screenshots, physical-device Focus behavior and distribution provisioning were not exercised locally. PR CI supplies canonical smoke coverage.
- The first signed release failed: the existing app Ad Hoc profile lacks Time Sensitive. Xcode also rejected the original extension declarations, which were removed after checking `DVTPortalCachedPortalCapabilities.json` supported product types. The app capability must be enabled and its Ad Hoc profile regenerated, then `APPLE_PROVISIONING_PROFILE` updated. Share/Widget profiles and the distribution certificate remain unchanged.

The local single-file UI report lists each missing before/after capture at `~/.local/share/ui-reports/tsk/clean-up-due-notifications-time-sensitive/report.html` (5,574 bytes). No browser was available for its phone-width rendering check.

Official contracts: [Time Sensitive interruption](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive), [Time Sensitive authorization uses the entitlement](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/timesensitive).
