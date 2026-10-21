# Calendar day overview in Today (#39)

The user selected the Day overview prototype: full event titles above thin duration bars across a compact horizontal day span. The production SwiftUI view has smaller, Dynamic Type text, no event dividers, no Calendar heading, and no routine explanatory footer. All-day events appear above the span. Events outside the chosen hours remain visible in compact rows below it; Calendar stays above tasks in the same scrolling list. Source selection, occurrence identity, local-day clipping and Taskwarrior behavior are unchanged.

Settings → Calendar controls Start hour and End hour. The default is 08:00–18:00; valid ranges run from 00:00 through 24:00 with the end strictly after the start. Settings persist across launches and are shared across windows in the process. These controls change the display span, not the EventKit query. Core validates saved values, projects events and hour ticks using the same local-date window (including daylight saving changes), and packs measured complete labels without colliding with labels or duration bars.

Native reads each event’s [source calendar color from EventKit](https://developer.apple.com/documentation/eventkit/ekcalendar/cgcolor) and converts it to sRGB. Today uses that color on the duration bar, or a small dot for all-day and outside-hour rows. Missing/unsupported colors use a secondary-color fallback; titles retain the system text color. Source color changes participate in snapshot equality without changing event identity. No calendar or event writes are introduced by the display path.

Missing access uses Enable Calendar. Undetermined/write-only access requests full read access; denied/restricted access opens the app’s system Settings. Full-access read errors show Calendar unavailable and Retry, clearing after a successful read. Empty Calendar reads render no Calendar section.

## Verification

- Core: 160 Swift Testing cases passed, including selected-hour clipping, preserved outside-hour events, instant events, saved-range validation, spring/fall boundaries and tick alignment, complete-label packing, and color-driven refresh without identity changes.
- Native: 175 Swift Testing cases reported, with 131 passed and 44 conditionally skipped. Two separate XCTest runner-fixture probes skipped as designed. Color tests cover sRGB, grayscale and missing values; the actual EventKit fixture checks unchanged source colors and that every owned displayed event carries the source color. External sync/Taskwarrior fixtures are not established by this host run.
- App controller package: 45 Swift Testing cases and six XCTest command checks passed, including persisted hours and recovery from corrupt/invalid preferences.
- Signed arm64 App/UI build-for-testing passed with Xcode 27.1. UI selection routing (14 Python checks) and CI routing checks passed. Full CI selects five Calendar presentation methods plus the two CalendarToday integration methods on both device families; smoke selection is unchanged.

## Runtime evidence and limits

All seven Calendar methods passed on iPhone 18 Pro and iPad Pro 13-inch (M5), iOS 27.0. The iPhone uses focused reruns after correcting Stepper selectors and full-row scrolling; the final Settings journey was rerun for the accessibility hour-value layout. The iPad passed all seven methods together.

CalendarPresentationUITests uses controlled source snapshots on isolated simulators with UUID test replicas. It checks populated, 22-event, empty Calendar/tasks, five access states, Retry recovery, largest accessibility text, Settings controls, valid hour bounds, persistence after relaunch, preserved outside-hour events, and task navigation/completion. Controlled permission states establish presentation and routing, not personal account behavior.

CalendarTodayUITests separately exercises actual EventKit and system permission dialogs against a token-owned LOCAL Calendar source. Its evidence includes `readOnlyVerified: true` and `calendarColorMatched: true`, source-change and foreground refresh, day-boundary exclusions, denial/system Settings, and ordinary task capture/completion after a Calendar failure.

The current-only mobile report omits historical iterations at the user’s request. It contains 22 captures and measures 621,010 bytes. Local file on this Mac: `/Users/julesseguin/.local/share/ui-reports/tsk/label-and-implement-issue-39/20261022/calendar-overview.html`. The 390 px preview decoded all 22 images, expanded all six sections with zero horizontal overflow, and verified tap-to-enlarge. iPad Settings sheet crops improve phone legibility; full-screen source captures are retained. Native dark appearance remains unverified: the simulator rendered light despite dark appearance requests, so mislabeled dark captures are excluded. No personal Calendar account, physical device/input, spoken VoiceOver, or distribution provisioning is established.

The source-color check compares displayed colors exactly with fresh EventKit readback. Comparing the initially assigned color with its saved value allows 0.000001 per channel because EventKit round-trips channels at Float precision.

Standards review found no hard violations or material smells. Spec review caught the DST tick/bar mismatch; it was fixed and covered by spring/fall assertions. No implementation findings remain; the dark-appearance evidence limitation remains explicit.

Disposable simulator ownership is recorded before each run; the test wrapper shuts down devices it boots on exit, and owned devices are deleted after capture. Existing booted devices are left alone.

The browser prototype and the user’s verdict are preserved outside main on [prototype/calendar-overview-39](https://github.com/Julesseg/tsk/tree/prototype/calendar-overview-39/App/Prototypes/CalendarOverview). Production uses Core and SwiftUI rather than embedding the browser prototype.
