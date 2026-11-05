# iOS development from Linux

Use `bash scripts/remote-ios.sh` to build the current Linux checkout on an
Apple silicon Mac over SSH. Core tests also run locally with
`swift test --package-path Core`. PR CI remains the canonical iPhone UI gate.

## Connect the Mac

In T3 Settings → Devices, select the Linux environment and add the Mac as a
Machine over SSH. Use its Tailscale hostname for access across networks.
Both machines need Tailscale connected; the Mac must be awake and unlocked.
Verify the SSH host key once through a trusted connection before using T3's
non-interactive connection. The Mac needs Xcode, Rust/rustup, Python 3 and
rsync. The launcher clears inherited Electron process flags before starting
Python. The helper adds `~/.cargo/bin` and Homebrew to the remote PATH.

The helper reads the single SSH source in `~/.t3/userdata/settings.json`
(`T3CODE_HOME` overrides the `.t3` directory). With several sources or outside
T3, select one with `TSK_REMOTE_HOST=user@mac` or `--host user@mac`.
SSH aliases use the caller's `~/.ssh/config`; T3 source ports and identity
files are also honored when choosing the source automatically.

```sh
bash scripts/remote-ios.sh doctor
bash scripts/remote-ios.sh build
```

`doctor` verifies the remote toolchain without booting a simulator. `build`
compiles the Rust bridge and the app with ad-hoc simulator signing.
`core` and `native` run the corresponding SwiftPM tests on the Mac. Native
tests needing an external fixture retain the same prerequisites as direct
`swift test`; these commands do not replace CI's native conformance harness.

## Inspect the app in T3

1. Use `device_list` to choose an iPhone on the same SSH host as the helper.
   Record the already-booted devices; `xcrun simctl list devices booted` on
   the Mac supplies the baseline for cleanup.
2. Build before booting: `bash scripts/remote-ios.sh build`.
3. Open the selected host/device with `device_open`. Keep its returned
   `agent-device` command for all app launches, input and recordings.
4. Run `bash scripts/remote-ios.sh install --device <UDID>`. It refreshes
   the build and installs into the already-booted device.
5. Launch `com.julesseguin.tsk` using that `agent-device` command and inspect
   it with `device_screenshot`.
6. On completion or failure, shut down only devices this task booted using
   `device_close` with `shutdown=true`. If no devices remain booted, quit
   Simulator on the Mac. Leave previously booted devices alone.

Installation replaces that simulator's app; choose a dedicated development
device when preserving an existing installation matters. The helper never
boots a simulator for `build` or `install`.

## Focused UI tests

Choose a dedicated test iPhone: UI tests modify app data and permissions.
Pass an explicit test selection; repeat `--only` for several classes/methods.

```sh
bash scripts/remote-ios.sh test --device <UDID> \
  --only TskUITests/TaskPresentationUITests/testVisibleCompletionRemovesEveryUpcomingAppearanceAndPersists
```

The helper uses `scripts/run-ui-tests.sh`, including its simulator ownership
and cleanup. Tests that boot a stopped simulator shut it down on success or
failure and preserve pre-existing boots. Tests requiring sync servers or
native keyboard fixtures need the existing CI setup; run those through CI.
Result bundles are copied to the local `.build/remote-ios/<run>/`, including
after a test failure when the SSH connection is still available. A broken
connection may require retrieving results from the printed Mac workspace.

## Source and build ownership

Each local machine/checkout gets a stable directory under the Mac's
`~/Library/Caches/tsk-remote/<checkout-key>/`. A lock rejects concurrent syncs
or builds for the same checkout. Mac source sync includes tracked edits and
untracked, nonignored source; deleted files disappear on the next sync.
`.git`, `.env` and `.env.*` files are excluded. Links inside the checkout are
copied as files; links outside it are rejected. Git history and ignored local
configuration are not copied. No Git commit or push is required to test edits.

Rust, SwiftPM and Xcode caches stay on the Mac, separately from Linux build
products. Existing Mac projects and T3 worktrees are untouched. Result bundles
accumulate per run; remove this helper's printed cache directory when the
checkout is retired and no command is using it.
