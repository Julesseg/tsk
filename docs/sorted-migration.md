# Migrate the working set to Sorted³

The migration script prepares a private bundle from a full Taskwarrior JSON export. Its Mac helper stages copies in a dedicated Apple Reminders list, which Sorted can import. It does not change Taskwarrior tasks, configure Sorted, stop the existing recurrence generator, or implement synchronization between the two apps.

## Prepare

Use a current, synchronized Taskwarrior client. To use its local database:

```bash
python3 scripts/migrate-taskwarrior-to-sorted.py \
  --timezone Europe/Paris \
  --output "$HOME/Downloads/tsk-sorted-migration"
```

Exporting disables Taskwarrior recurrence generation and garbage collection. To work from an existing full JSON export instead, add `--input /path/to/taskwarrior.json`. A filtered export is insufficient for preserving historical records and recurring-template relationships. Keep the original Taskwarrior database as well as the bundle for recovery.

The output directory must be new and outside this checkout. It is private and contains task data; do not commit it. Copy the whole bundle to the Mac, retaining its files and receipts together. Python 3.9+ with IANA time-zone data is needed to prepare it; macOS 14+ and Xcode command-line tools are needed to stage it.

## Mapping and limits

- All pending/waiting tasks are staged, including undated work and generated recurring occurrences. Completed/deleted records remain in the archive.
- The earlier of Scheduled and Deadline becomes the destination date; the sole date is used when only one exists. Original timestamps and both fields remain in the archive and notes. The selected IANA zone controls local dates/times and DST; midnight remains a valid time.
- Annotations become Reminders notes. Source UUID, project, tags, priority, original dates, waiting constraints, dependencies and recurrence details are recorded in notes. Priority also maps to the native Reminders priority.
- Project/tag structure and waiting/dependency enforcement are not transferred automatically. Confirm what Sorted retains and organize lists/tags separately.
- Recurring templates are listed in `manual-series.json`, not flattened into extra tasks. Set repeat rules on the appropriate imported occurrence in Sorted and check future dates. No Reminders repeat rules or alarms are created.

## Stage and verify

Follow the generated `README.md` and `review.md`. First run the offline validator, stage the synthetic sample and inspect its import inside Sorted. Verify sync, backup/export recovery and notes/date retention before the full transfer.

```bash
cd "$HOME/Downloads/tsk-sorted-migration"
./run-mac.sh validate
./run-mac.sh sample
./run-mac.sh verify-sample
```

Once the sample has been checked in Sorted:

```bash
./run-mac.sh apply --sample-checked
./run-mac.sh verify
```

In Sorted's Reminders settings, change the selected source from the sample list to the full staging list printed by the helper. Sorted's [developer response](https://apps.apple.com/ro/app/sorted-calendar-notes-tasks/id1306893526), under “Broken Import,” confirms import from one list and completion of source reminders. Field fidelity in the installed app is a separate runtime check.

The helper preserves existing reminders and uses source UUIDs plus local receipts for retry protection. Completed source reminders still count as staged. If a saved reminder disappears, apply does not recreate it; verification reports the missing reminder. Never prepare a fresh bundle merely to retry an existing transfer, since doing so can duplicate tasks. If the staging list disappears or receipt/manifest hashes conflict, reconcile the transfer before continuing.

After all tasks, lists and recurring series are checked, coordinate the old capture/import and recurrence jobs at cutover and use Sorted as the sole daily editor. Keep the source archive and track trial changes. Returning requires a verified Sorted export or reconciliation; the tool does not provide an automatic rollback of trial edits.

## Tool checks

```bash
python3 scripts/test-sorted-migration.py
```

The conversion tests cover date precedence, DST/midnight, Unicode and multiline notes, recurrence separation, archived records, input rejection, private bundle permissions, cleanup and safe export flags. Offline validation and Mac compilation do not prove delivery or field retention in Sorted.
