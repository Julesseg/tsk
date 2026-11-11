# Find saved tasks with named filters

Find Tasks returns a native list of rich task entities, suitable for explicit
iteration into later task actions. It reads the same durable TaskChampion data
as the app; it does not open a URL to perform a Shortcut. Each entity has the
same full UUID, description, project, tags, priority, Scheduled, Deadline,
Waiting until, status and Open Task URL properties as Add Task.

## Filters and URLs

Use `tsk://find` with these optional query arguments:

| Argument | Meaning |
| --- | --- |
| `description` | Case-insensitive contained text, using the POSIX locale; literal text, never filter syntax |
| `project` | Exact UTF-8 bytes, including case; child projects do not match. Empty selects no project |
| `tags` (repeatable) | Every tag must match its exact UTF-8 bytes |
| `status` | `unfinished` (default, pending), `completed`, or `all` (pending and completed only) |
| `priority` | `H`, `M`, `L`, or empty for no priority |
| `scheduled-from`, `scheduled-through` | Inclusive Scheduled timestamp bounds |
| `deadline-from`, `deadline-through` | Inclusive Deadline timestamp bounds |
| `waiting-until-from`, `waiting-until-through` | Inclusive Waiting until timestamp bounds |
| `sort` | One of the choices below; defaults to `created-desc` |
| `limit` | Positive integer; omitted returns every match |
| `offset` | Nonnegative integer; defaults to zero |
| `x-success`, `x-error` | Caller URLs using the Add Task callback rules |

Every supplied filter must match. No arguments selects all unfinished tasks.
Deleted records and recurring templates are excluded even for `all`.
A bounded date must exist on the record; missing or invalid record dates do
not match a supplied bound. `from <= date <= through`; either side may be
omitted and equal bounds are valid. Reversed or invalid bounds fail.
URL dates use ISO 8601 timestamps with explicit timezones, as in Add Task.
Percent-encode query values, especially `+` in timezone offsets and callback
URLs. Unknown arguments, duplicate non-tag arguments, unknown status/sort,
invalid priorities, and invalid/overflowing pagination fail explicitly.
Shortcuts exposes these same named inputs with native dates and enums.

## Ordering and pages

| Sort | Order |
| --- | --- |
| `created-desc` | Newest creation timestamp first (default) |
| `created-asc` | Oldest creation timestamp first |
| `description-asc` | Case-sensitive UTF-8 byte order |
| `scheduled-asc` | Earliest Scheduled timestamp first |
| `deadline-asc` | Earliest Deadline timestamp first |
| `waiting-until-asc` | Earliest Waiting until timestamp first |
| `priority-desc` | H, M, L, then absent/unrecognized priority |

Dates sort numerically. Missing or invalid sort dates come last, including
creation dates. Equal primary values use newest creation first, then full UUID
ascending. Pages apply offset then limit after sorting. Offset beyond the
matches succeeds with an empty list. There is no implicit result cap.
Determinism applies to a fixed dataset; concurrent edits can move tasks between
pages, so callers that need a fixed snapshot should consume one list.

## Results and presentation

Without callbacks, the app shows a temporary Find Tasks sheet, including an
explicit empty state. Tasks open into their usual details. Dismissing returns
to the existing workspace. No custom view is created and favorites are not
changed. The list is a snapshot of that request, not a saved live query.
Navigation first settles valid edits and retains invalid drafts using the
existing Add Task navigation guard. Existing Settings and integration panels
report a navigation error above the current panel; finish that panel and retry
the URL, rather than replacing an open form with competing results.

With a callback, the `result` query argument contains JSON:

```json
{"success":true,"tasks":[{"uuid":"full UUID","description":"Book train","project":"Travel","tags":["rail"],"priority":"H","scheduled":null,"deadline":null,"waitingUntil":null,"status":"pending","openTaskURL":"tsk://open-task?id=full-UUID"}]}
```

No matches returns `{"success":true,"tasks":[]}`. Read success does not claim
`savedLocally`. tsk rejects an encoded callback above its own 8192-byte ceiling
with `result_too_large`; it never truncates the list. This is an application
limit, not a universal safe callback URL size. The caller or OS may reject a
smaller URL. Use filters, limit and offset to request smaller pages. Delivery
failure is displayed in tsk and does not automatically repeat the request.

## Verification boundaries

Core action tests cover combined filters, exact versus child projects, distinct
Unicode byte identities, every-tag matching, statuses, inclusive/invalid ranges,
numeric sorting and UUID ties, empty results, uncapped lists and pagination.
Core URL tests cover decoding, validation and rich list JSON/oversize errors.
The persistent Native test reopens actual storage with pending, completed,
deleted and recurring records. Apple-framework tests execute the real intent,
read rich entities and pass one directly to Complete Task.

`TaskActionURLUITests` retains the Add URL journeys and adds actual installed
caller-to-tsk URL delivery, visible matching/empty results, task navigation,
workspace retention, callback pages, empty callbacks and oversized failure.
These methods run in full iPhone coverage, not PR smoke. The artifact verifier
checks all fourteen extracted Find inputs and six native date bounds.

Local test/build results and the UI report are recorded in the PR. Direct
`perform()` tests and extracted metadata do not prove discovery or invocation
by the external Shortcuts app or Siri. Full iPhone CI, actual Shortcuts workflow
execution, physical-device provisioning and suspended/background execution must
be reported separately. Native iPad support is retired under ADR 0007; iPhone
is canonical for this issue despite the older issue's iPad wording.

## Local implementation evidence

- Core: 189 tests pass, including five structured Find contract cases.
- Native: 134 cases executed successfully; 50 existing environment-gated cases
  skipped without the real sync server, pinned Taskwarrior or owned Spotlight
  fixtures. The new persistent Find and real intent cases both execute and pass.
- Controller package: 73 tests pass; the extended task URL panel/draft guard
  regression also passes after the presentation fix.
- UI selection: 16 selection tests pass, preserving eight smoke methods and
  selecting all 82 full methods (45 workspace / 37 task-row).
- CI execution: 11 tests pass; simulator-lease runner checks: three pass.
- Signed generic arm64 simulator build-for-testing passes. Artifact admission
  verifies fourteen Find inputs, native dates, native entity-list output and
  existing App/Share/Widget entitlements and shortcuts.
- Standards review: zero actionable findings. Spec review: no confirmed contract
  defects; the open-panel concern was addressed with the existing navigation
  guard and an installed URL regression.

No local simulator was booted for this issue. Multiple bounded lease attempts
were refused while another session owned the Mac's simulator. Populated/empty
results, task-detail navigation, Settings refusal and real caller callbacks
have checked-in XCUITest assertions and screenshot attachments, but were not
executed locally. The UI-report builder declined to create an HTML report with
zero captures; no visual report or screenshot evidence is claimed. Full iPhone
CI and external Shortcuts discovery/invocation remain pending acceptance.
