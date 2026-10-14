# Task annotations

Task detail presents timestamped notes separately from the description. Native add/edit sheets support multiline text, visible validation/write failures, explicit keyboard dismissal, and Command-Return to save. The same section and editor are used in iPhone navigation and the iPad detail column. Unsupported task states retain their existing mutation restrictions.

Core stores notes in independent `annotation_<epoch seconds>` attributes. Adding uses the injected clock's integral Unix second and increments one second until the exact raw key is free, matching pinned Taskwarrior 3.5.0 `Task::addAnnotation`. TaskChampion's high-level add operation would overwrite a colliding key, so Core performs the collision check under the existing semantic mutation lease. Concurrent managers sharing the native replica use that lease across read/check/commit.

Editing addresses the complete byte-exact raw key and updates only that note plus `modified`. It keeps the original timestamp/key, other notes, description, task UUID, and unfamiliar attributes. Validation rejects blank-only text; successful writes preserve the supplied text bytes, including leading/trailing whitespace and multiline contents. Failed validation or storage remains a failure. Successful durable add/edit operations request the existing automatic synchronization workflow.

Reading retains every raw annotation-prefixed entry. Numeric timestamps are displayed chronologically; unrecognized suffixes remain visible with their raw key. Distinct raw keys such as `annotation_01` and `annotation_1` remain distinct, even when their parsed instants coincide. Generic attribute updates reject annotation keys in favor of these dedicated operations.

## Verified

- Core public TaskManager tests: collision increments, read/edit identity, unchanged description/dates/opaque fields, byte-exact Unicode, malformed suffix preservation, missing-reference/blank validation, unchanged tasks after failed writes, unsupported-task restrictions, concurrent adds, and automatic synchronization after add/edit commits. Full suite: 50 passed.
- Actual TaskChampion persistence: two independent managers add at the same injected second without losing either note; editing and reopening preserve both raw identities, malformed entries, dates, and opaque fields.
- Actual Taskwarrior 3.5.0 export reads canonical timestamp notes with the expected UTC timestamps and exact multiline text. A Taskwarrior `annotate` operation is then visible through the native Core interface and preserves the native edits.
- An additional real compatibility probe establishes that Taskwarrior 3.5.0 rejects the noncanonical suffix `01` during export (exit 2, diagnostic that `01` is not a valid date). The failed desktop read leaves the exact native entries unchanged. Preservation of such existing data is supported; successful Taskwarrior export of noncanonical raw timestamps is not claimed.
- Signed generic arm64 App and XCUITest compilation passes. Shared App Group entitlement and create/find intent metadata verification passes.

## UI and device evidence

The canonical iPhone suite and dedicated iPad lane both include `TaskAnnotationUITests`. Its real native flow captures blank validation, multiline add/review, a collision creating a second note, edit-in-place, and persistent reopen with both exact timestamp identities. It uses the shared virtualized-form reveal helper and keeps screenshot attachments. A command issued while the annotation sheet is open must not open background capture; detail-hosted panels suspend workspace commands while preserving their own editor shortcuts.

No local simulator was booted, and no new screenshot was captured on this disk-constrained Mac. Compilation is not UI execution: both canonical device jobs must run against the integration revision. Physical keyboard connection, key delivery, and device behavior remain unverified; injected simulator key events are separate evidence.
