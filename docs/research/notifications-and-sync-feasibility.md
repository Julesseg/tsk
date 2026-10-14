# Notification and synchronization feasibility

Research date: 2026-10-14. Taskwarrior source findings are pinned to `v3.5.0`;
its `libshared` date implementation is pinned to
`86935551e0faa56ed14c52802a23280a593df338`. This note records facts and open
product choices. Accepted policies are recorded below and in the product direction.

The interview has established offline task use with synchronization as soon as
possible through a TaskChampion server, and notifications derived from scheduled
and deadline times. Different times each trigger an alert, and coincident times
produce one combined alert. Completion/deletion cancels pending alerts when known
locally. Settings allow a configurable notification-time fallback for midnight
dates without rewriting task dates. The replacement starts enabled at 09:00 in
the device's current time zone, adjustable or disabled in settings. Newly learned
missed alerts fire immediately after reconciling the final synced state, except
for completed/deleted tasks. Delivered-notification cleanup remains open.

## Synchronized dates do not preserve input precision

TaskChampion stores timestamps as integer UNIX epoch values. In Taskwarrior
`v3.5.0`, `ColumnTypeDate::modify` evaluates the date input and stores only its
resulting epoch value. The date-only constructor in the pinned date library uses
local midnight; explicitly supplying `00:00:00` gives the same resulting instant.
[TaskChampion task model](https://gothenburgbitfactory.org/taskchampion/tasks.html),
[Taskwarrior date mutation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/columns/ColTypeDate.cpp#L161),
[pinned date constructors](https://github.com/GothenburgBitFactory/libshared/blob/86935551e0faa56ed14c52802a23280a593df338/src/Datetime.cpp#L102)

Consequently, `tsk` cannot reliably distinguish an ordinary synchronized date-only
deadline from an explicitly timed midnight deadline using that value alone. It
also cannot recover the original time zone or input precision from an epoch
timestamp. This is an inference from the stored representation and inspected
mutation path; it is not an upstream date-only classification feature.

TaskChampion allows application-defined attributes. Such attributes could retain
precision or time-zone information for values created by `tsk`, but that would
require a project policy for validation and subsequent edits by other clients.
It would not automatically supply metadata for ordinary imported Taskwarrior
dates. [Additional attributes](https://gothenburgbitfactory.org/taskchampion/tasks.html)

Treating midnight as evidence of a date-only value would therefore be a heuristic,
with a risk of reinterpreting real midnight deadlines. The user chose an optional,
configurable notification-time fallback for midnight values. This is a convention
for notification timing, not a change to task dates or recovery of lost precision.

## Local notification delivery and reconciliation

Apple's local notification system can deliver a registered request while the app
is not running. Calendar triggers match the supplied date components, and
`nextTriggerDate()` exposes the next date satisfying those conditions. Requests
remain active until they trigger or the app cancels them; Apple's scheduling guide
specifically gives completion of a reminder as a reason to cancel it.
[Scheduling guide](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app),
[nextTriggerDate](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger/nexttriggerdate())

Scheduling a new request with the identifier of a pending request replaces it.
Pending requests can be canceled by identifier. Removing notifications already
shown in Notification Center uses separate delivered-notification APIs.
[Identifier behavior](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier),
[pending cancellation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)),
[notification center APIs](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)

Stable identifiers based on the task UUID and notification event kind would allow
the app to reconcile changed scheduled/deadline values without accumulating
duplicate pending requests. This is an implementation implication of the API,
not a settled identifier convention for the project.

A local task completion can cancel its pending notification while offline. A
completion or date change on another replica cannot affect an already registered
phone notification until `tsk` receives that change and reconciles the schedule.
Thus a previously scheduled notification may still fire for a task completed on
desktop while the phone has stale data. This is an inference combining replica
synchronization with local notification registration, rather than an automatic
cross-device cancellation behavior.
[TaskChampion synchronization model](https://gothenburgbitfactory.org/taskchampion/sync-model.html),
[local scheduling guide](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

## Pending capacity is not verified for the current API

Apple explicitly documents retaining the nearest 64 scheduled notifications for
the deprecated `UILocalNotification` API. This bounded research did not find an
equally explicit current Apple contract stating that limit for
`UNNotificationRequest`. The legacy number must not be presented as a verified
modern limit. [Legacy notification documentation](https://developer.apple.com/documentation/uikit/uilocalnotification)

The current notification center API supports inspecting pending requests. A
bounded nearest-event queue and read-back verification are implementation options;
the exact modern capacity and behavior at that capacity need device verification.
Neither a queue size nor an event-priority policy is decided by this note.
[Current pending-request APIs](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)

## Background synchronization is opportunistic

`BGTaskRequest.earliestBeginDate` sets the earliest permitted start, not a guaranteed
execution time. Apple notes that scheduled background work may wait many hours
before launch. Periodic background work therefore cannot promise immediate
receipt of remote task edits or completions.
[Earliest begin date](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate),
[background task development guide](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development)

For the accepted "sync as soon as possible" intent, active app execution provides
an opportunity to attempt synchronization immediately, while suspended execution
depends on system-granted opportunities. Accepted foreground triggers are task
changes, app opening, and connectivity return, with visible status and retry.
Background mechanisms remain implementation decisions. Local reminders can
use previously registered schedules without requiring a background sync at their
firing time, but those schedules reflect the most recent data the app processed.
[Local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

## Open product choices

- Whether task completion removes delivered notifications as well as pending
  ones.
- How to prioritize future notifications if the app must schedule a bounded set.

## Verification limits

No notification delivery, pending-capacity, time-zone, or background synchronization
test was run on an iOS device for this note. Date storage conclusions follow the
pinned source and TaskChampion model; platform scheduling conclusions follow Apple
documentation. Outstanding notification choices are listed above.
