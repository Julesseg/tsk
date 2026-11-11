# Add Task automation

Add Task in Shortcuts and `tsk://add` save one task immediately to durable local storage, including offline. Success does not acknowledge server synchronization. Neither interface presents a confirmation editor. The Add Task adapter belongs to the app target, so Shortcuts runs it in the app process rather than the widget extension. Other actions are being rebuilt in separate issues.

## Inputs

| Shortcuts input | URL argument | Meaning |
| --- | --- | --- |
| Description | `description` | Required nonblank text |
| Project | `project` | Optional project name |
| Tags | repeated `tags` | One tag per argument, for example `tags=trip&tags=rail` |
| Priority | `priority` | `H`, `M`, `L`; omit for no priority |
| Scheduled | `scheduled` | Intended work timestamp |
| Deadline | `deadline` | Independent deadline timestamp |
| Waiting until | `waiting-until` | Independent waiting constraint |

Shortcuts uses native dates. URLs require ISO 8601 timestamps with an explicit timezone: `2026-11-05T10:30:00+02:00` or `2026-11-05T08:30:00Z`. Percent-encode each query value, including the `+` in a timezone as `%2B`. Storage has whole-second precision; fractional seconds are discarded. Omitted dates remain unset. Description and project are ordinary text, never Taskwarrior command syntax. Tags follow task tag validation; names containing spaces and all-uppercase reserved tags are rejected.

```text
tsk://add?description=Buy%20milk
tsk://add?description=Book%20train&project=Travel&tags=trip&tags=rail&priority=H&scheduled=2026-11-05T10%3A30%3A00%2B02%3A00&deadline=2026-11-06T08%3A00%3A00Z&waiting-until=2026-11-04T09%3A00%3A00Z
```

Routes are deliberately unversioned. Future additions must preserve these meanings. Unknown arguments, duplicate arguments (except repeated `tags`), missing values, unsupported priority/tags, malformed timestamps, paths, fragments and credentials are rejected before creation. Custom attributes, annotations, dependencies and recurrence are outside this action.

## Results and navigation

Shortcuts returns a Task entity with Full UUID, Description, Project, Tags, Priority, Scheduled, Deadline, Waiting until, Status and Open Task URL. Entity resolution uses the durable UUID. The Open Task URL is `tsk://open-task?id=<full UUID>`; working-set numbers and partial UUIDs are rejected.

Without callbacks, Add Task refreshes the current workspace. The saved task appears as an ordinary row wherever it matches the current view and filters; no destination page or editor is opened. Explicit Open Task links use the existing task-link navigation with a route back. Existing valid task edits are saved before executing the URL; validation or save failure keeps the draft and reports the error. A URL received while another unsupported editing panel is open reports an error rather than discarding that panel.

## Callbacks

Supply optional `x-success` and `x-error` absolute caller URLs as encoded query values. tsk appends a single percent-encoded `result` argument containing JSON, preserving the caller's existing query bytes and repeated arguments. The caller must not already use a `result` argument. Callbacks may use caller-owned schemes or HTTPS; `tsk`, `file`, `javascript`, `data` and `about` schemes, credentials and fragments are rejected. Callback base URLs may occupy at most 4096 UTF-8 bytes. Treat callback contents as task data and choose a trusted receiver.

```text
tsk://add?description=Buy%20milk&x-success=myapp%3A%2F%2Fdone%3Frequest%3D42&x-error=myapp%3A%2F%2Ferror%3Frequest%3D42
```

Success JSON (unset properties are `null`, tags an array, dates UTC timestamps):

```json
{"success":true,"savedLocally":true,"task":{"uuid":"12345678-1234-1234-1234-123456789ABC","description":"Buy milk","project":null,"tags":[],"priority":null,"scheduled":null,"deadline":null,"waitingUntil":null,"status":"pending","openTaskURL":"tsk://open-task?id=12345678-1234-1234-1234-123456789ABC"}}
```

Failure JSON uses `success:false`, `savedLocally:false`, and `error:{"code":"invalid_input","message":"…"}`. Storage, navigation and unsupported-route failures are reported with a descriptive code/message. An invalid callback itself is reported in tsk, since an unvalidated destination cannot receive errors.

The final encoded callback URL has an 8192-byte limit. Oversized results are reported as `result_too_large`, never truncated. If saving already succeeded, this error has `savedLocally:true` and the saved `uuid`, and is sent to `x-error` (or `x-success` if no error callback was supplied). If only one callback is provided, it receives either outcome; the JSON success flag distinguishes them. Failed OS delivery after saving explicitly reports local success and the UUID. It does not undo storage or automatically retry creation. A caller that retries an Add URL explicitly creates another task.

A successful OS URL-open acknowledgement means the system accepted delivery; it is not an acknowledgement that the caller processed the JSON.

## Modify Task

Modify Task in Shortcuts and `tsk://modify?id=<full UUID>` change exactly one saved task. Select a Task entity in Shortcuts; URLs accept only its full UUID, never a numeric ID, partial UUID, filter or task list. For bulk workflows, use Find followed by explicit iteration. Modify replaces the old standalone Reschedule action; saved shortcuts using Reschedule may break. Delete and the remaining named navigation actions are tracked separately.

The seven fields use the same names and date formats as Add. All omitted values preserve existing data. Empty optional text or an empty Shortcuts tag list also preserves data, including with Replace selected. Blank Description preserves the saved description. Clear project, Clear priority, Clear Scheduled, Clear Deadline and Clear Waiting until remove those optional fields; URLs use `clear-project=true`, `clear-priority=true`, `clear-scheduled=true`, `clear-deadline=true`, and `clear-waiting-until=true`. Clear arguments accept only `true` or `false`. Supplying a nonempty value and its Clear control together is an error.

Tag operation (`tag-operation` in URLs) offers Add, Remove, Replace and Clear. Add is the default. Repeat `tags` for individual tags. Add and Remove act on byte-exact names; Replace replaces all tags when values are supplied. Omitted/empty tag lists preserve tags in these three modes. Clear explicitly removes all tags and rejects supplied tag values. Canonically equivalent Unicode spellings remain distinct.

```text
tsk://modify?id=12345678-1234-1234-1234-123456789ABC&project=Travel&tags=rail&tag-operation=add&scheduled=2026-11-05T08%3A30%3A30Z&clear-deadline=true
tsk://modify?id=12345678-1234-1234-1234-123456789ABC&tag-operation=clear&clear-priority=true
```

All fields validate and save together under the shared mutation lease. A failed validation or persistence operation leaves the saved task unchanged. Completed tasks remain editable; deleted and missing tasks report errors. Identity, completion state, unknown attributes, annotations and unrelated fields are preserved. Recurring templates remain guarded; generated occurrences use the existing atomic occurrence bookkeeping and cannot clear their required Deadline. No raw recurrence attributes are accepted.

Modify uses the same durable offline acknowledgement, rich Task entity and JSON callbacks described above. Callback encoding/delivery failure after saving does not undo or replay the operation. Without callbacks it reveals the saved task through the existing linked-task navigation, even when its changed dates or project no longer match the current view. The existing draft gate saves valid edits before modifying and retains invalid drafts without applying the action.
