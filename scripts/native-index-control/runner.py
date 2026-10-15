import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import selectors
import signal
import stat
import subprocess
import sys
import time
import uuid


BUNDLE = "com.julesseguin.tsk.native-index-control"
CASES = [(protection, order) for protection in ("protected", "default-named")
         for order in ("delete-first", "index-first")]
OBSERVATION_SECONDS = 120
MAX_RECEIPT_BYTES = 65536
STAGES = {"protected-data.availability", "index.availability", "observation.finished", "app.main-actor.heartbeat"} | {
    operation + "." + phase for operation in ("initial-delete", "cleanup-delete", "index", "inserted-query", "empty-query")
    for phase in ("submit", "returned", "callback")}


class CommandFailure(Exception):
    def __init__(self, stage, code):
        super().__init__(stage)
        self.stage = stage
        self.code = code


class Interrupted(Exception):
    def __init__(self, signum):
        self.code = 128 + signum


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


class Commands:
    def __init__(self, output):
        self.output = output
        self.sequence = 0

    def run(self, args, stage, timeout=60, env=None):
        self.sequence += 1
        destination = self.output / f"command-{self.sequence:03d}-{stage}.log"
        with destination.open("wb") as log:
            try:
                child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         env=env, start_new_session=True)
            except OSError as error:
                raise CommandFailure(stage, 70) from error
            selector = selectors.DefaultSelector()
            selector.register(child.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + timeout
            total = 0
            parent_exit_time = None
            pipe_held_open = False
            try:
                while child.poll() is None or selector.get_map():
                    now = time.monotonic()
                    if child.poll() is not None and parent_exit_time is None:
                        parent_exit_time = now
                    if parent_exit_time is None and now >= deadline:
                        raise CommandFailure(stage, 124)
                    if parent_exit_time is not None:
                        try:
                            os.killpg(child.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    for key, _ in selector.select(0.05):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if not chunk:
                            selector.unregister(key.fileobj)
                        else:
                            total += len(chunk)
                            if total > 1024 * 1024:
                                raise CommandFailure(stage + ".output-limit", 70)
                            log.write(chunk)
                    if parent_exit_time is not None and time.monotonic() - parent_exit_time >= 0.25 and selector.get_map():
                        pipe_held_open = True
                        break
                code = child.wait()
            finally:
                selector.close()
                child.stdout.close()
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=2)
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        write_json(destination.with_suffix(".json"), {"stage": stage, "exit": code,
                                                     "bytes": total, "pipeHeldOpen": pipe_held_open})
        if code:
            raise CommandFailure(stage, code if code > 0 else 128 - code)
        return destination.read_text(errors="replace").strip()


def available_device(document):
    candidates = [(runtime, device) for runtime, devices in document["devices"].items()
                  if ".iOS-" in runtime for device in devices
                  if device.get("isAvailable") and device["name"].startswith("iPhone")]
    if not candidates:
        raise CommandFailure("no-installed-iPhone-runtime", 70)
    return max(candidates, key=lambda item: (tuple(int(n) for n in item[0].split(".iOS-")[1].split("-")),
                                              "Pro" in item[1]["name"], item[1]["name"]))


def read_receipt(path, expected):
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(descriptor, "rb") as source:
        metadata = os.fstat(source.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_RECEIPT_BYTES:
            raise ValueError("invalid receipt size or file type")
        raw = source.read(MAX_RECEIPT_BYTES + 1)
    document = json.loads(raw)
    if len(raw) > MAX_RECEIPT_BYTES or not isinstance(document, dict) or document.get("configuration") != expected:
        raise ValueError("receipt identity mismatch")
    if document.get("outcome") not in ("pending", "completed", "api-error", "query-mismatch"):
        raise ValueError("invalid native outcome")
    if not isinstance(document.get("events"), list) or len(document["events"]) > 64:
        raise ValueError("invalid event bound")
    domain = "tsk.native-control." + expected["token"]
    if set(document) != {"configuration", "domain", "indexName", "itemIdentifier", "pid", "outcome", "events"}:
        raise ValueError("invalid receipt fields")
    if (document["domain"] != domain or document["itemIdentifier"] != domain + "/item" or
            document["indexName"] != "tsk.native-control." + expected["protection"] + "." + expected["token"] or
            type(document["pid"]) is not int or not 0 < document["pid"] < 2 ** 31):
        raise ValueError("invalid native identity")
    heartbeat_count = 0
    last_heartbeat_uptime = None
    for event in document["events"]:
        if (not isinstance(event, dict) or event.get("stage") not in STAGES or
                not {"stage", "time", "uptime", "mainThread"} <= set(event) or
                set(event) - {"stage", "time", "uptime", "mainThread", "error", "count", "exactIdentity", "available", "heartbeatOrdinal"}):
            raise ValueError("invalid native event fields")
        if event["stage"] == "app.main-actor.heartbeat":
            heartbeat_count += 1
            if (set(event) != {"stage", "time", "uptime", "mainThread", "heartbeatOrdinal"} or
                    event["mainThread"] is not True or type(event["heartbeatOrdinal"]) is not int or
                    event["heartbeatOrdinal"] != heartbeat_count or heartbeat_count > 24):
                raise ValueError("invalid heartbeat schema or sequence")
        elif "heartbeatOrdinal" in event:
            raise ValueError("unexpected heartbeat ordinal")
        for field in ("time", "uptime"):
            value = event[field]
            if type(value) not in (int, float) or not 0 <= value < 2 ** 53 or not math.isfinite(value):
                raise ValueError("invalid native timestamp")
        if event["stage"] == "app.main-actor.heartbeat":
            if last_heartbeat_uptime is not None and event["uptime"] - last_heartbeat_uptime < 5 - 1e-6:
                raise ValueError("invalid heartbeat interval")
            last_heartbeat_uptime = event["uptime"]
        for field in ("mainThread", "available", "exactIdentity"):
            if field in event and type(event[field]) is not bool:
                raise ValueError("invalid native boolean")
        if "count" in event and (type(event["count"]) is not int or not 0 <= event["count"] < 2 ** 31):
            raise ValueError("invalid native count")
        if "error" in event:
            error = event["error"]
            if (not isinstance(error, dict) or set(error) != {"domain", "code"} or
                    not isinstance(error["domain"], str) or len(error["domain"]) > 200 or
                    type(error["code"]) is not int or abs(error["code"]) >= 2 ** 53):
                raise ValueError("invalid native error")
    return document


def observe(path, expected, destination, started):
    latest = None
    deadline = started + OBSERVATION_SECONDS
    while True:
        if time.monotonic() >= deadline:
            return latest or {"configuration": expected, "outcome": "pending", "events": [],
                              "receiptMissing": True}
        current = read_receipt(path, expected)
        if current is not None:
            latest = current
            write_json(destination / "native-receipt.json", current)
            if current["outcome"] != "pending":
                return current
        time.sleep(min(0.5, max(0, deadline - time.monotonic())))


def cleanup_device(commands, identifier, name):
    results = []
    for operation in ("shutdown", "delete"):
        try:
            commands.run(["xcrun", "simctl", operation, identifier], name + "." + operation, timeout=30)
            results.append({"stage": operation, "exit": 0})
        except (CommandFailure, Interrupted, OSError) as error:
            results.append({"stage": operation, "exit": getattr(error, "code", 70),
                            "interrupted": isinstance(error, Interrupted)})
    try:
        remaining = json.loads(commands.run(["xcrun", "simctl", "list", "devices", "booted", "--json"],
                                            name + ".remaining-booted", timeout=20))
        if not any(device.get("state") == "Booted" for devices in remaining["devices"].values() for device in devices):
            commands.run(["osascript", "-e", 'quit app "Simulator"'], name + ".quit-simulator", timeout=20)
        results.append({"stage": "remaining-booted", "exit": 0})
    except (CommandFailure, Interrupted, ValueError, KeyError, OSError) as error:
        results.append({"stage": "remaining-booted", "exit": getattr(error, "code", 70),
                        "interrupted": isinstance(error, Interrupted)})
    return results


def recover_created_device(commands, runtime, owned_name, name):
    document = json.loads(commands.run(["xcrun", "simctl", "list", "devices", "--json"],
                                      name + ".recover-created", timeout=20))
    matches = [str(uuid.UUID(device["udid"])) for device in document["devices"].get(runtime, [])
               if device.get("name") == owned_name]
    if len(matches) > 1:
        raise ValueError("ambiguous owned simulator name")
    return matches[0] if matches else None


def run_cells(commands, output, app, observe=observe):
    result = {"schema": 1, "purpose": "supplemental-native-control-not-app-acceptance", "cells": [],
              "outcome": "pending", "observationSecondsPerCell": OBSERVATION_SECONDS}
    code = 0
    try:
        result["initialBooted"] = json.loads(commands.run(
            ["xcrun", "simctl", "list", "devices", "booted", "--json"], "initial-booted"))
        runtime, device = available_device(json.loads(commands.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"], "available-devices")))
        result.update(runtime=runtime, deviceType=device["deviceTypeIdentifier"])
        for protection, order in CASES:
            name = protection + "-" + order
            cell = {"name": name, "outcome": "setup-pending", "cleanup": []}
            result["cells"].append(cell)
            destination = output / name
            destination.mkdir()
            identifier = None
            interruption = None
            token = str(uuid.uuid4()).upper()
            owned_name = "tsk native index " + token
            cell["ownedName"] = owned_name
            try:
                identifier = str(uuid.UUID(commands.run(
                    ["xcrun", "simctl", "create", owned_name,
                     device["deviceTypeIdentifier"], runtime], name + ".create")))
                cell["ownedDevice"] = identifier
                write_json(output / "result.json", result)
                for operation, timeout in (("boot", 30), ("bootstatus", 120), ("install", 60)):
                    args = ["xcrun", "simctl", operation, identifier]
                    if operation == "bootstatus":
                        args.append("-b")
                    if operation == "install":
                        args.append(str(app))
                    commands.run(args, name + "." + operation, timeout=timeout)
                configuration = {"token": token, "protection": protection, "order": order,
                                 "bundle": BUNDLE}
                cell["configuration"] = configuration
                environment = dict(os.environ, SIMCTL_CHILD_TSK_INDEX_TOKEN=configuration["token"],
                                   SIMCTL_CHILD_TSK_INDEX_PROTECTION=protection, SIMCTL_CHILD_TSK_INDEX_ORDER=order)
                started = time.monotonic()
                cell["launch"] = commands.run(["xcrun", "simctl", "launch", identifier, BUNDLE],
                                               name + ".launch", env=environment)
                container = commands.run(["xcrun", "simctl", "get_app_container", identifier, BUNDLE, "data"],
                                         name + ".container")
                observation_started = time.monotonic()
                cell["hostObservation"] = {"startEpochSeconds": time.time()}
                write_json(output / "result.json", result)
                try:
                    receipt = observe(Path(container) / "Documents/native-index-control.json", configuration,
                                      destination, started)
                finally:
                    observation_ended = time.monotonic()
                    cell["hostObservation"].update(endEpochSeconds=time.time(),
                                                  elapsedSeconds=observation_ended - observation_started,
                                                  launchInclusiveElapsedSeconds=observation_ended - started)
                cell["native"] = receipt
                cell["outcome"] = receipt["outcome"]
                if receipt["outcome"] != "completed":
                    code = code or 1
            except (CommandFailure, Interrupted, ValueError, KeyError, OSError) as error:
                cell["outcome"] = "interrupted" if isinstance(error, Interrupted) else "setup-failed"
                cell["failedStage"] = getattr(error, "stage", type(error).__name__)
                if isinstance(error, Interrupted):
                    interruption = error
                raise
            finally:
                cleanup_interruption = None
                if identifier is None:
                    try:
                        identifier = recover_created_device(commands, runtime, owned_name, name)
                        cell["recoveredOwnedDevice"] = identifier
                    except (CommandFailure, Interrupted, OSError, ValueError, KeyError) as error:
                        cell["cleanupRecoveryExit"] = getattr(error, "code", 70)
                        if isinstance(error, Interrupted):
                            cleanup_interruption = error
                if identifier:
                    cell["cleanup"] = cleanup_device(commands, identifier, name)
                    if any(stage["exit"] for stage in cell["cleanup"]):
                        code = 70
                    if cleanup_interruption is None:
                        first = next((stage for stage in cell["cleanup"] if stage.get("interrupted")), None)
                        if first:
                            cleanup_interruption = Interrupted(first["exit"] - 128)
                if cleanup_interruption is not None:
                    cell["outcome"] = "interrupted"
                write_json(output / "result.json", result)
                if interruption is None and cleanup_interruption is not None:
                    raise cleanup_interruption
            if code == 70:
                raise CommandFailure(name + ".cleanup", 70)
        result["outcome"] = "completed" if code == 0 else "native-incomplete"
    except Interrupted as error:
        code = error.code
        result["outcome"] = "interrupted"
    except (CommandFailure, ValueError, KeyError, OSError) as error:
        code = getattr(error, "code", 70)
        result.update(outcome="setup-failed", failedStage=getattr(error, "stage", type(error).__name__))
    result["exit"] = code
    write_json(output / "result.json", result)
    summary = {key: result[key] for key in ("schema", "purpose", "outcome", "exit")}
    summary["cells"] = [{"name": cell["name"], "outcome": cell["outcome"],
                         "events": len(cell.get("native", {}).get("events", [])), "cleanup": cell["cleanup"]}
                        for cell in result["cells"]]
    print("TSK_NATIVE_INDEX_CONTROL_V1 " + json.dumps(summary, separators=(",", ":")), flush=True)
    return code


def build(commands, output):
    source = Path(__file__).with_name("NativeIndexControl.swift")
    architecture = platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise CommandFailure("unsupported-host-architecture", 70)
    sdk = commands.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], "sdk-path")
    metadata = {"xcode": commands.run(["xcodebuild", "-version"], "xcode-version"),
                "sdk": commands.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], "sdk-version"),
                "architecture": architecture, "bundle": BUNDLE, "target": architecture + "-apple-ios17.0-simulator",
                "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest()}
    app = output / "NativeIndexControl.app"
    app.mkdir()
    info = {"CFBundleExecutable": "NativeIndexControl", "CFBundleIdentifier": BUNDLE,
            "CFBundleName": "NativeIndexControl", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "MinimumOSVersion": "17.0",
            "LSRequiresIPhoneOS": True, "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            "UIDeviceFamily": [1], "UILaunchScreen": {}}
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    commands.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "6", "-sdk", sdk,
                  "-target", architecture + "-apple-ios17.0-simulator", "-parse-as-library", str(source),
                  "-o", str(app / "NativeIndexControl"), "-framework", "UIKit", "-framework", "CoreSpotlight"],
                 "compile", timeout=120)
    commands.run(["codesign", "--force", "--sign", "-", str(app)], "sign")
    commands.run(["codesign", "--verify", "--deep", "--strict", str(app)], "verify-signature")
    commands.run(["codesign", "-d", "--verbose=4", "--entitlements", ":-", str(app)], "signature-details")
    metadata["executableSHA256"] = hashlib.sha256((app / "NativeIndexControl").read_bytes()).hexdigest()
    write_json(output / "build.json", metadata)
    return app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build-only", action="store_true")
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True, exist_ok=False)

    def interrupted(signum, frame):
        raise Interrupted(signum)

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    commands = Commands(arguments.output)
    try:
        app = build(commands, arguments.output)
        return 0 if arguments.build_only else run_cells(commands, arguments.output, app)
    except (CommandFailure, Interrupted, OSError, ValueError) as error:
        code = getattr(error, "code", 70)
        write_json(arguments.output / "result.json", {"outcome": "build-failed", "exit": code,
                                                       "failedStage": getattr(error, "stage", type(error).__name__)})
        return code


if __name__ == "__main__":
    sys.exit(main())
