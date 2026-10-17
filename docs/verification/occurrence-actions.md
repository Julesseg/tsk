# Occurrence-only actions

Pending generated occurrences have explicit **Edit occurrence** and **Complete occurrence** actions in task details, row actions, and Upcoming. The template remains a separate record and navigation destination. Completed occurrences stay in history and cannot be edited here. Creation and raw attribute edits cannot change parent/index/mask links.

The common `TaskManager.update`, `complete`, rescheduling, annotation, dependency and typed-attribute actions use the same occurrence path. Native Complete/Reschedule App Intents therefore use it too. A shared filesystem semantic lease covers validation and the durable mutation across app participants. It never covers a network wait.

`TaskAtomicMutatingReplica.updateAtomically` requires full byte-exact expected snapshots and patches. Unsupported adapters fail; there is no sequential fallback. The native adapter wraps upstream SQLite storage, checks expected maps inside each serializable SQLite transaction, then calls upstream `Replica.commit_operations` once with the occurrence and parent operations. The final transaction also updates TaskChampion’s operation log and working set. SQLite rollback preserves all of these when a storage write fails. This uses TaskChampion’s dataset and synchronization protocol.

Completion changes only the occurrence’s status/end/start/modified fields and its existing parent-mask position to `+`. Ordinary occurrence edits preserve all unrelated attributes and positions; wait changes update `W`/`-` using the saved wait instant, consistent with Taskwarrior’s derived waiting state. A generated due date cannot be cleared. Missing or malformed links, duplicate sibling positions, unknown mask characters, out-of-range positions and disagreeing terminal states fail without inventing or repairing masks. Repeating a completion with a matching `+` is idempotent.

Local transaction atomicity and cross-process leases do not make simultaneous offline edits on independent replicas a distributed transaction. TaskChampion still resolves synchronization according to its upstream property-operation semantics. No new mask merge protocol or generation logic is introduced.

## Verification

Ticket #21 was checked against immutable native bridge snapshots and a real TaskChampion sync server 0.7.1 with Taskwarrior 3.5.0:

- Public Core behavior: occurrence-only edits/completion, preserved siblings/opaque fields, malformed links and masks, reserved fields, due preservation, wait states and idempotence.
- Real SQLite trigger aborts operation-log insertion after task-map writes: neither task changes nor new operations survive. Canonically equivalent but byte-different expected attributes reject the batch.
- Two actual processes call the public completion API on different siblings; both completed states and both mask positions survive reopening.
- Real native `Intent.perform` reschedules and completes an occurrence in the dataset later reopened by the app factory.
- Encrypted native → desktop → native round trip: native completes one occurrence, desktop completes another, a later designated-generator report creates the next position, UUIDs/history/unknown attributes survive, mask advances `++-` to `++--`.
- Durable occurrence completion finishes while actual HTTP GET or server-accepted POST responses remain held. Retry converges at an independent encrypted peer.

Generator test reports must have separate registered client identities. `with-sync-fixture.py` authorizes and exports `TSK_SYNC_TEST_GENERATOR_20_CLIENT_ID` through `_23_CLIENT_ID` so concurrent report tests cannot generate each other’s templates under a different timezone or horizon. Manually configured single-client fixtures can run individual generator tests using `TSK_SYNC_TEST_CLIENT_ID`; do not run multiple generator suites concurrently on that shared identity.

The signed generic simulator App and XCUITest compile verifies the UI code and embedded metadata, not runtime interaction. Canonical iPhone/iPad `RecurringTemplateUITests` exercise occurrence edit/completion/reopen using a recorded real Taskwarrior-generated fixture. These captures are pending CI; no local simulator was booted. Host App Intent execution does not prove system Siri/Shortcuts discovery, account configuration, physical devices, or background opportunities.
