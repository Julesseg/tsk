# Taskwarrior → Sorted migration bundle

This bundle stages copies of unfinished Taskwarrior tasks in a dedicated Apple Reminders list. Configure Sorted³ to import that list. The source export, original dates and task fields stay in `source.json`; no Taskwarrior tasks are changed or deleted.

The Mac helper requires macOS 14+, Xcode command-line tools, and Reminders access. Run it from Terminal on the Mac. It embeds a privacy usage description and signs its local helper. No simulator is used.

## Check the sample first

1. Read `review.md`. It contains the exact counts, date mapping, task preview and recurring-series checklist.
2. Run `./run-mac.sh validate`. This checks the bundle without accessing Reminders.
3. Run `./run-mac.sh sample` and grant Reminders access if requested. This creates three synthetic tasks in a separate list whose name ends in `· sample`.
4. Run `./run-mac.sh verify-sample` to check the staged Reminders fields.
5. In Sorted's Reminders settings, select only that sample list. Verify all three tasks arrive, notes keep both lines and the link, the undated task stays undated, and the timed tasks use the expected local time. For Europe/Paris the sample times are 14:37 on 15 January 2030 and midnight at the start of 16 January. Check priority if you rely on it. Test iPhone ↔ Mac sync and Sorted export/backup recovery before the full transfer.

Sorted's developer documents importing from one Reminders list and marking imported source reminders completed. Exact menus and field retention in your installed version require this check. A completed staging reminder is not proof of a correct Sorted import.

## Stage the working set

After checking the sample:

```bash
./run-mac.sh apply --sample-checked
./run-mac.sh verify
```

Select the full staging list shown by the helper in Sorted's Reminders settings, replacing the sample list. Check task counts and representative notes/dates after import. The bridge preserves project names and tags in notes; arrange Sorted lists/tags separately. Waiting/dependency fields are retained as notes, without enforcing those constraints.

Recurring templates are **not** imported as ordinary tasks or automatic Reminders repeats. Their unfinished generated occurrences are staged once, with the original repeat details in notes. Use `manual-series.json` and `review.md` to configure repetition on the appropriate imported occurrence in Sorted; preserve other outstanding occurrences as single tasks. Compare the next occurrence dates, including monthly boundaries and any end condition. This manual step is required before calling the migration complete.

Keep the entire bundle, including `receipt.json` and `receipt-sample.json`. Rerunning the same bundle recognizes existing reminders even after Sorted marks them completed. The receipt prevents recreating already-staged reminders that were subsequently removed. A crash after a Reminders commit is recovered by matching source UUIDs still present in the staging list. If the staging list itself disappears, the helper stops. Do not generate another bundle to retry an existing transfer; it can create duplicates.

After verifying the complete transfer and repeat rules, use Sorted as the sole everyday editor for the trial. Coordinate the Taskwarrior capture/import and recurrence jobs at cutover; this tool does not stop services. Preserve the original Taskwarrior data and this export. Returning requires reconciling task changes made during the trial; this tool does not claim an automated Sorted → Taskwarrior reverse migration.

## Commands

- `validate`: offline schema, date and source-checksum validation.
- `check`: current Reminders authorization, without requesting access or changing lists.
- `sample`: stage three synthetic examples, safely repeatable with the same bundle.
- `verify-sample`: verify the source sample fields in Reminders.
- `apply --sample-checked`: stage all unfinished tasks after the sample has been checked in Sorted.
- `verify`: verify all source staging reminders; source completion is allowed.

Original timestamps are compared as instants. The earlier Scheduled/Deadline value wins, and the specified IANA time zone determines the displayed local time. Midnight remains a time; no midnight alarm is added.

## Sources and verification boundary

- [Sorted developer response about Reminders import](https://apps.apple.com/ro/app/sorted-calendar-notes-tasks/id1306893526), “Broken Import,” 4 May 2023.
- [Sorted URL scheme](https://www.sortedapp.com/blog/url-scheme): supports capture and list/tags, but does not document notes, repeat-rule input or a bulk importer.
- [Apple EventKit reminders](https://developer.apple.com/documentation/eventkit/ekreminder).

Offline tests and compilation establish the export and staging-tool behavior only. They do not establish preservation inside Sorted, its sync or a usable recovery export. Those checks are part of the sample and trial setup above.
