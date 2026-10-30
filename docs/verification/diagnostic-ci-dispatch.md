# Diagnostic CI dispatch

Use an explicit suite and reason after pushing a frozen source branch:

```sh
python3 scripts/dispatch-ui-tests.py --ref <branch> --suite diagnostic \
  --reason 'Compare native transport failure at the frozen source'
```

Diagnostic selects the existing 12-method iPhone subset and skips the Linux
Core/Native jobs. `keyboard` and `text` select focused coverage on both families;
`full` selects complete coverage with two partitions per family. The manual form
default is smoke, not full. See [CI test tiers](ci-test-tiers.md).

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
