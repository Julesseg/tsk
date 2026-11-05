import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile


def run(command, cwd, environment):
    print("+ " + shlex.join(str(value) for value in command), flush=True)
    process = subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL, start_new_session=True)
    def stop(signum, frame):
        if process.poll() is None:
            os.killpg(process.pid, signum)
            process.wait()
        raise SystemExit(128 + signum)
    previous = {kind: signal.signal(kind, stop) for kind in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]}
    try:
        status = process.wait()
        if status:
            raise subprocess.CalledProcessError(status, command)
    finally:
        for kind, handler in previous.items():
            signal.signal(kind, handler)


def sync_snapshot(stream, workspace, environment):
    source = workspace / "source"
    source.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="incoming-", dir=workspace) as temporary:
        staging = Path(temporary)
        with tarfile.open(fileobj=stream, mode="r|gz") as archive:
            for entry in archive:
                path = PurePosixPath(entry.name)
                if path.is_absolute() or ".." in path.parts or not entry.isfile():
                    raise ValueError(f"Invalid source archive member: {entry.name}")
                target = staging / path
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(entry) as incoming, target.open("wb") as output:
                    shutil.copyfileobj(incoming, output)
                target.chmod(entry.mode & 0o777)
                os.utime(target, (entry.mtime, entry.mtime))
        run(["rsync", "-ac", "--delete", "--exclude=.build/", "--exclude=Native/Bridge/target/",
             "--exclude=Native/Artifacts/", str(staging) + "/", str(source) + "/"], workspace, environment)
    return source


def execute(request, workspace, source, environment):
    action = request["action"]
    if action == "sync":
        return
    if action == "doctor":
        for command in [["xcodebuild", "-version"], ["swift", "--version"], ["cargo", "--version"],
                        ["rustup", "target", "list", "--installed"], ["xcrun", "simctl", "list", "devices", "booted"]]:
            run(command, source, environment)
        print(f"Available disk: {shutil.disk_usage(workspace).free // (1024 ** 3)} GiB", flush=True)
        return
    if action == "core":
        run(["swift", "test", "--package-path", "Core"], source, environment)
        return
    if action == "native":
        run(["bash", "scripts/build-native.sh", "host"], source, environment)
        environment["TSK_TASKCHAMPION_LIBRARY"] = str(source / "Native/Bridge/target/release/libtsk_taskchampion.dylib")
        run(["swift", "test", "--package-path", "Native"], source, environment)
        return
    run(["bash", "scripts/build-native.sh", "simulator"], source, environment)
    derived = workspace / "DerivedData"
    build = ["-project", "App/Tsk.xcodeproj", "-scheme", "Tsk", "-derivedDataPath", str(derived),
             "ARCHS=arm64", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM="]
    if action == "test":
        results = workspace / "results" / request["run"]
        results.mkdir(parents=True)
        run(["bash", "scripts/run-ui-tests.sh", request["device"], *build,
             "-resultBundlePath", str(results / "Tests.xcresult"),
             *["-only-testing:" + value for value in request["only"]]], source, environment)
        bundles = list(results.glob("*.xcresult"))
        passed = 0
        for bundle in bundles:
            summary = json.loads(subprocess.check_output(
                ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"],
                env=environment, text=True))
            (results / (bundle.stem + "-summary.json")).write_text(json.dumps(summary, indent=2) + "\n")
            if summary.get("failedTests", 0) or summary.get("skippedTests", 0):
                raise ValueError("Focused UI verification contains failed or skipped tests; inspect the result bundles.")
            passed += summary.get("passedTests", 0)
        if not passed:
            raise ValueError("No UI tests passed; check --only identifiers and simulator prerequisites.")
        print(f"Focused UI verification: {passed} passed, no failures or skips.", flush=True)
        return
    run(["xcodebuild", "build", "-destination", "generic/platform=iOS Simulator", *build], source, environment)
    app = derived / "Build/Products/Debug-iphonesimulator/Tsk.app"
    print(f"Simulator app: {app}", flush=True)
    if action == "install":
        state = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "--json"], env=environment))
        if not any(device["udid"] == request["device"] and device["state"] == "Booted"
                   for entries in state["devices"].values() for device in entries):
            raise ValueError("Open this host/device with T3 device_open before installing. No simulator was booted by this helper.")
        run(["xcrun", "simctl", "install", request["device"], str(app)], source, environment)


def main():
    request = json.loads(sys.argv[1])
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise ValueError("The native simulator bridge requires an Apple silicon Mac with Xcode.")
    if not re.fullmatch(r"[0-9a-f]{20}", request["key"]) or not re.fullmatch(r"[0-9a-f]{32}", request["run"]):
        raise ValueError("Invalid remote workspace identity.")
    workspace = Path.home() / "Library/Caches/tsk-remote" / request["key"]
    workspace.mkdir(parents=True, exist_ok=True, mode=0o700)
    environment = dict(os.environ)
    environment.pop("ELECTRON_RUN_AS_NODE", None)
    environment["PATH"] = f"{Path.home()}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:" + environment.get("PATH", "/usr/bin:/bin")
    with (workspace / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another remote command is using this checkout. Wait for it to finish before syncing.")
        source = sync_snapshot(sys.stdin.buffer, workspace, environment)
        environment["CARGO_TARGET_DIR"] = str(source / "Native/Bridge/target")
        execute(request, workspace, source, environment)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"remote-ios worker: {error}", file=sys.stderr)
        sys.exit(error.returncode if isinstance(error, subprocess.CalledProcessError) and error.returncode > 0 else 1)
