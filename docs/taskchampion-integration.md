# Native TaskChampion integration

tsk pins TaskChampion **3.1.0** (`Native/Bridge/Cargo.toml` and its committed
Cargo.lock). Taskwarrior **3.5.0** is the compatibility reference: its
[bridge manifest](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/taskchampion-cpp/Cargo.toml)
uses TaskChampion 3.1.0. This pin does not claim that every Taskwarrior command,
filter or recurrence operation is already implemented by tsk.

`TaskManager` is the public Core behavior interface. `TaskReplica` is its
external-storage boundary; `TaskChampionReplica` in `Native/` implements it.
Core has no Rust or platform framework dependency. Its tests run with
`swift test --package-path Core`, including on Linux.

The bridge is a small C ABI over the pinned upstream Rust library. It uses
TaskChampion's actual `SqliteStorage`, `TaskData`, and `commit_operations`,
not a separate task database. Creation is committed in one replica transaction
before success is returned. Task records retain UUIDs and the complete raw
attribute map. Each request reopens storage, so reads from separate instances
observe prior commits rather than an app-owned snapshot.

Ordinary draft capture currently supports pending tasks. Recurring templates,
occurrences and unfamiliar states remain readable with their attributes intact;
unsupported creation is rejected. This adapter does not generate occurrences,
claim sync success, or replace Taskwarrior validation.

## Build and test

Install Rust **1.99.0** through rustup (use the minimal profile). Cargo.lock
pins the entire native dependency graph. Build the host integration:

```sh
scripts/build-native.sh host
TSK_TASKCHAMPION_LIBRARY="$PWD/Native/Bridge/target/release/libtsk_taskchampion.dylib" swift test --package-path Native
```

On Linux use `libtsk_taskchampion.so`. The native tests call the same Core
`TaskManager` as the app against real isolated replicas. They cover reopening,
unknown fields, independent local clients, and genuine storage failure. With
`TSK_TASKWARRIOR_BINARY=/path/to/task`, an additional real Taskwarrior 3.5.0
check exports a native capture and edits it while retaining opaque fields,
annotations, tags, and identity.

Before building the Xcode app, run on a Mac with Xcode:

```sh
scripts/build-native.sh apple
xcodebuild test -project App/Tsk.xcodeproj -scheme Tsk -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

The script builds arm64 devices and arm64/x86_64 simulators and assembles a
universal simulator archive. Artifacts are ignored and rebuilt in CI, including
signed archive workflows. The app statically links the bridge; the host tests
load the built library explicitly. CI retains the independent fast Core lane,
adds a Linux real-replica lane, and builds the bridge before XCUITest.

The app stores its replica in its Application Support directory. UI tests use
an isolated random subdirectory and preserve it through terminate/relaunch.
A successful local save is independent of any future server synchronization.
Simulator tests do not establish physical-device persistence after OS eviction,
physical keyboard interaction, external-server convergence, or recurrence
compatibility.
