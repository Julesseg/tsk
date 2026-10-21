# Compact Calendar in Today (#39)

The Calendar source, local-day clipping, ordering, event selection, occurrence identity and Taskwarrior behavior are unchanged. Today renders each event's clipped time range (or All day) and title; time uses the snapshot time zone. At accessibility text sizes, time sits above the wrapping title. No Calendar header, location, calendar name, continuation explanation, routine footer or empty-state row is rendered.

Missing access uses Enable Calendar. Undetermined/write-only access requests full read access; denied/restricted access opens the app's system Settings. Unavailable access can retry the authorization request. Full-access read errors show Calendar unavailable and Retry; errors clear on a successful read. Existing events and task rows remain in the same scrolling Today list, with Calendar above tasks.

Runtime evidence is collected from signed debug simulator builds using canonical XCUITest. CalendarPresentationUITests injects CalendarEventSource snapshots only on an isolated simulator with a UUID test replica, and exercises Today, actual task navigation/completion, Retry and Enable actions. Its controlled permission states establish presentation and routing, not real account authorization. CalendarTodayUITests separately exercises actual EventKit and system permission dialogs against a token-owned local Calendar source.

No personal Calendar account, physical device, VoiceOver speech, distribution signing or provisioning is established by those tests.

## Local checks

- Core: 156 Swift Testing cases passed, including the four Calendar date/access/recovery regressions.
- Native: 174 Swift Testing cases reported, with 130 passed and 44 conditionally skipped; two additional XCTest runner-fixture probes skipped as designed outside their separate fixture runs. The 14 focused Calendar tests passed. Live sync/Taskwarrior scenarios requiring their external fixtures were not established by this host run.
- App controller package: 44 Swift Testing cases and six XCTest command checks passed.
- Signed arm64 App/UI build-for-testing passed using Xcode 27.1.
- UI selection routing: 14 Python checks passed; the four new presentation methods are included in the iPad full selection. Smoke selection is unchanged.

## Runtime evidence

The six Calendar presentation/integration methods passed on iPhone 18 Pro and iPad Pro 13-inch (M5), iOS 27.0. They cover populated, 22-event, empty Calendar/tasks, five access states, appearance changes, accessibility XXXL text, task navigation/completion, and Retry recovery. The two error/recovery methods passed again on both families after the accessibility error row was changed to a vertical layout to avoid a broken word. A final iPad capture run uses full-screen XCTest screenshots because app-only landscape exports had an orientation/cropping defect.

The actual EventKit journey verified source readback unchanged (`readOnlyVerified: true`, LOCAL source type 0), timed/all-day/spanning events and day-boundary exclusions, EventKit changes, foreground refetch, actual permission denial, opening system Settings and task capture after denial. The read-failure workflow verifies ordinary task capture/completion separately; successful Retry recovery uses an explicitly controlled source, not a personal account.

The full-screen iPad run passed all six methods again, and the report contains 96 screenshots in 22 sections. The temporary baseline helper is removed from the committed source. The matching baseline renderer is `35acafc` with the same controlled Calendar source and task data injected; the baseline renderer itself was not changed. iPhone captures use portrait app screenshots, while iPad captures use full-screen XCTest screenshots in landscape (the separate actual EventKit journey also captures portrait).

Local report on this Mac: `/Users/julesseguin/.local/share/ui-reports/tsk/label-and-implement-issue-39/20261021/report.html`.

Only the owned disposable simulator UDIDs were booted, and each test wrapper shut down its device on exit. The devices are removed after evidence collection. No already-booted simulator was present at the initial inventory.
