# Shared saved-view integration fix

The app's saved-view store previously used private Application Support, while
`TaskChampionSession.open` configured no definition store. The shared native
factory now injects `LocalTaskViewStore` beside the App Group replica database,
and the app uses that factory too. These definitions remain device-local
metadata: they do not become synchronized task attributes. The obsolete private
Application Support helper is removed. This corrects an unshipped cache layout;
existing private cache files are not deleted or overwritten.

`saveView` and `deleteView` now hold the common mutation lease across their
entire awaited read-modify-save operation. Reentrant calls, independent
managers and separate app processes cannot overwrite another definition from
a stale snapshot. Readers see atomic files. View-only mutations do not request
task synchronization. A Core manager without the optional view store now
reports storageNotConfigured on read as well as write, while ordinary task
queries continue to work.

Red public-boundary tests reproduced the missing factory store, four lost-update
assertions across reentrant and independent managers, and an unconfigured read
silently returning an empty list. Real native tests verify factory reopen,
same-manager/two-manager/two-process saves, overlapping deletion/creation,
no-sync metadata updates, and existing durable task/view lifecycles.

Local Core45 and actual Native39 tests pass, including real Taskwarrior3.5,
encrypted fixture synchronization, mutation probes and storage failures.
Generic signed app/UI compilation and artifact verification are recorded in the
external handoff. No simulator was booted; canonical iPhone/iPad UI execution
and physical device/keyboard behavior remain separate evidence. The report
`/tmp/tsk-issue-3/shared-views-ui-report.html` lists missing captures explicitly.
