# Diagnostic CI dispatch

Use an explicit suite and reason after pushing a frozen source branch:

```sh
python3 scripts/dispatch-ui-tests.py --ref <branch> --suite diagnostic \
  --reason 'Verify the selected UI scenario at the frozen source'
```

Diagnostic selects the existing 27 on-demand iPhone methods and skips the Linux
Core/Native jobs. `text`, `regression` and `menu` select focused iPhone coverage;
`full` selects the nightly coverage with workspace and row-editing partitions.
The manual form defaults to smoke. See [CI test tiers](ci-test-tiers.md).

The helper resolves the branch, checks matching source/branch/suite work before
dispatch, and rejects a branch move during admission. It can reuse successful
completed evidence only with a matching explicit toolchain/runtime identity.
Always verify the actual returned run's SHA. No source-ref override exists.

A failed diagnostic requires a classified, targeted job rerun or a new controlled
experiment with an explicit reason. Do not repeatedly dispatch full coverage to
refresh status. At most one targeted retry for an evidenced infrastructure
failure. Original failures remain part of the evidence.

Manual suite groups preserve in-flight runs; PR/push and nightly use separate
groups. Concurrent clients can still race, and separate coverage can still
contend for runners. The helper and concurrency controls are not proof of runner
capacity. Focused results supplement actual full coverage; they cannot replace
native input, system-delivery or canonical branch-protection acceptance.
