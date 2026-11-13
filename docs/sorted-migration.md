# Migrate the working set to Sorted³

The prepared Mac bundle runs with one command:

```bash
~/Downloads/tsk-sorted-migration/run-mac.sh
```

It sends unfinished tasks directly to Sorted through the [documented Add URL](https://www.sortedapp.com/blog/url-scheme). No Reminders, permission setup, sample run or manual verification commands are required. The importer handles validation, pacing and a dispatch receipt automatically. Projects map to lists, tags pass through, and the earlier of Scheduled/Deadline becomes the date in the selected local time zone. Undated tasks omit the URL's date parameter. The URL accepts minute precision; original timestamps stay in the archive.

## Prepare another bundle

For maintainers, the exporter reads a full JSON export or the local Taskwarrior database:

```bash
python3 scripts/migrate-taskwarrior-to-sorted.py --timezone Europe/Paris --output "$HOME/Downloads/tsk-sorted-migration"
```

Use a synchronized source client. Add `--input /path/to/taskwarrior.json` for an existing full export. Local export disables recurrence generation and garbage collection. The new output directory must be outside the checkout; its files are private and must not be committed. Copy the whole bundle to the Mac. Python 3.9+ and IANA time-zone data are required; the importer does not compile native code.

## Fields requiring attention

The URL interface does not document notes, recurrence, priority or waiting/dependency inputs. The exporter generates `manual-work.md` with the actual notes and repeat rules to copy afterward, plus other affected fields. Tags containing commas are reported there rather than split into different tags. Full original records, timestamps and historical tasks remain in `source.json`.

Recurring templates remain in `manual-series.json`; unfinished occurrences are sent as individual tasks. Configure repetition on the appropriate imported occurrence, preserving other outstanding occurrences as single tasks. The script does not stop the existing generator or implement cross-app synchronization.

## Receipt and verification boundary

`import-state.json` tracks requests dispatched to Sorted. Rerunning the same bundle skips recorded requests. A crash between dispatch and receipt update leaves an uncertain task; the next run identifies it and requires resolving that request as already sent or safe to retry. Concurrent import processes are blocked. Bundles with old Reminders receipts stop to prevent mixing the two routes.

The URL interface does not acknowledge durable saving or expose task retrieval. A successful run therefore proves dispatch, not destination counts, sync or backup recovery. The source remains untouched, and original data is archived. Returning after the trial requires reconciling changes made in Sorted.

Tests run with `python3 scripts/test-sorted-migration.py`. They cover date precedence, DST/midnight, source preservation, URL encoding, direct dispatch, repeat-run skipping, interruption handling and offline validation. Dispatch tests use a fake opener and never create real tasks.
