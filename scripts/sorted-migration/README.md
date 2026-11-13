# Import into Sorted³

Run this one command on your Mac:

```bash
./run-mac.sh
```

It opens Sorted and sends all unfinished tasks directly through Sorted's Add URL. Projects become lists, tags are passed through, and the earlier of Scheduled/Deadline becomes the task date. There is no Reminders setup, compiler step, permission prompt or sample gate. For about 100 tasks, allow roughly two minutes.

The full source is preserved in `source.json`. Completed/deleted history is kept there without being sent. `import-state.json` records requests already sent, so rerunning the same bundle skips those requests. Keep the bundle together; creating a new bundle or deleting the receipt can cause duplicates.

Sorted's [documented URL interface](https://www.sortedapp.com/blog/url-scheme) cannot receive notes, repeat rules, priority, waiting constraints or dependencies. `manual-work.md` contains the affected tasks and exact notes/rules to copy afterward. Recurring templates are not duplicated as ordinary tasks; their existing unfinished occurrences are sent once. Tags containing commas are also listed for manual transfer because the URL uses commas as separators. The full original fields remain in the archive.

A successful dispatch means macOS accepted the URL; Sorted does not return a durable-save acknowledgement through this interface. If the process is interrupted while sending a task, it stops on the next run instead of blindly duplicating that request. The error identifies the task and explains how to resolve that one uncertain request. Ordinary completed reruns need no special options.

Python 3.9+ with time-zone data is required. Optional `--dry-run` validates without opening apps. `review.md` is an optional inventory, not a required checklist. Actual Sorted saving/sync remains a runtime boundary; no automatic reverse migration of trial edits is provided.
