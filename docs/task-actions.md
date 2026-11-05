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

Without callbacks, tsk reveals the task in a containing list and expands its row. Back returns to the prior workspace. Existing valid task edits are saved before leaving; validation or save failure keeps the draft and reports the error. A URL received while another unsupported editing panel is open reports an error rather than discarding that panel.

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
