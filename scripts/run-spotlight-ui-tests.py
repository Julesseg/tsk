#!/usr/bin/env python3
import argparse
import importlib.util
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys


SCRIPTS = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ui_selection", SCRIPTS / "ui-test-selection.py")
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class Interrupted(Exception):
    def __init__(self, number):
        self.status = 128 + number


def write_manifest(path, manifest):
    path = pathlib.Path(path)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(path)


def execute(command, environment):
    child = subprocess.Popen(command, env=environment)
    try:
        return child.wait()
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=30)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def remove_device(identifier, shutdown=True):
    outcomes = {}
    for action in (("shutdown", "delete") if shutdown else ("delete",)):
        try:
            cleanup = subprocess.run(["xcrun", "simctl", action, identifier], check=False, timeout=30)
            outcomes[action] = cleanup.returncode
        except (OSError, subprocess.TimeoutExpired) as error:
            outcomes[action + "Error"] = str(error)
    return outcomes


def cleanup_manifest(path):
    if not pathlib.Path(path).exists():
        return 0
    manifest = json.loads(pathlib.Path(path).read_text())
    owned = {case["device"] for case in manifest["cases"] if "device" in case} - {manifest["template"]}
    state = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True))
    devices = {device["udid"]: device for devices in state["devices"].values() for device in devices}
    status = 0
    for identifier in sorted(owned & devices.keys()):
        outcomes = remove_device(identifier, shutdown=devices[identifier]["state"] == "Booted")
        for case in manifest["cases"]:
            if case.get("device") == identifier:
                case["fallbackCleanup"] = outcomes
        status = status or outcomes.get("delete", 1)
        write_manifest(path, manifest)
    return status


def run(template, arguments):
    filters = [arg for arg in arguments if arg.startswith(("-only-testing:", "-skip-testing:"))]
    methods = sorted(test for test in selection.selected_methods(filters) if selection.matches(test, "TskUITests/SpotlightUITests"))
    if not methods:
        raise ValueError("Spotlight phase contains no selected tests")
    common = [arg for arg in arguments if arg not in filters]
    result = pathlib.Path(common[common.index("-resultBundlePath") + 1]).resolve()
    del common[common.index("-resultBundlePath"):common.index("-resultBundlePath") + 2]
    products = pathlib.Path(common[common.index("-derivedDataPath") + 1]) / "Build/Products/Debug-iphonesimulator"
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"]
    templates = [(runtime, device) for runtime, devices in devices.items() for device in devices if device["udid"] == template]
    if len(templates) != 1:
        raise ValueError("Expected one available simulator template: " + template)
    runtime, device = templates[0]
    evidence = pathlib.Path(os.environ.get("TSK_EVENTKIT_EVIDENCE_DIR", result.parent / "spotlight-evidence")) / "spotlight"
    evidence.mkdir(parents=True, exist_ok=True)
    manifest = {"template": template, "runtime": runtime, "cases": []}

    def persist():
        write_manifest(evidence / "phases.json", manifest)

    status = 0
    environment = dict(os.environ, TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR="1")
    for method in methods:
        name = method.rsplit("/", 1)[-1]
        case = {"method": method, "stage": "create"}
        manifest["cases"].append(case)
        directory = evidence / name
        directory.mkdir(parents=True, exist_ok=True)
        identifier = None
        try:
            persist()
            identifier = subprocess.check_output(["xcrun", "simctl", "create", "tsk Spotlight " + name, device["deviceTypeIdentifier"], runtime], text=True).strip()
            case.update(device=identifier, stage="boot")
            persist()
            print(f"Spotlight phase: {method}, fresh simulator {identifier}, runtime {runtime}", flush=True)
            subprocess.run(["xcrun", "simctl", "boot", identifier], check=True)
            subprocess.run(["xcrun", "simctl", "bootstatus", identifier, "-b"], check=True)
            case["stage"] = "install"
            persist()
            subprocess.run(["xcrun", "simctl", "install", identifier, str(products / "Tsk.app")], check=True)
            case["stage"] = "test"
            case["result"] = str(result.with_name(result.stem + "-spotlight-" + name + ".xcresult"))
            persist()
            command = [
                "xcodebuild", "test-without-building", "-destination", "platform=iOS Simulator,id=" + identifier,
                "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "600",
                "-maximum-test-execution-time-allowance", "600", *common,
                "-only-testing:" + method, "-resultBundlePath", case["result"],
            ]
            if os.environ.get("CI") == "true":
                command = [sys.executable, str(SCRIPTS / "relay-ui-test-boundaries.py"), "--device", identifier,
                           "--evidence", str(directory), "--owned-simulator", "--", *command]
            code = execute(command, environment)
            if code < 0:
                code = 128 - code
            case.update(stage="finished", status=code)
            status = status or code
        except subprocess.CalledProcessError as error:
            case.update(status=error.returncode, error=str(error))
            status = status or error.returncode
        except OSError as error:
            case.update(status=1, error=str(error))
            status = status or 1
        except Interrupted as error:
            case["status"] = error.status
            raise
        finally:
            if identifier:
                try:
                    container = subprocess.run(["xcrun", "simctl", "get_app_container", identifier, "com.julesseguin.tsk", "data"], capture_output=True, text=True, timeout=20)
                    if container.returncode == 0 and container.stdout.strip():
                        documents = pathlib.Path(container.stdout.strip()) / "Documents"
                        for path in documents.glob("*fixture-*.json"):
                            shutil.copy2(path, directory / path.name)
                except (OSError, subprocess.TimeoutExpired) as error:
                    case["evidenceError"] = str(error)
                outcomes = remove_device(identifier)
                case.update(outcomes)
                status = status or outcomes.get("delete", 1)
            persist()
        if case.get("status") in (130, 143):
            break
    return status


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--template")
    mode.add_argument("--cleanup-manifest")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.cleanup_manifest:
        return cleanup_manifest(args.cleanup_manifest)

    def interrupt(number, _frame):
        raise Interrupted(number)

    for number in (signal.SIGINT, signal.SIGTERM):
        signal.signal(number, interrupt)
    try:
        return run(args.template, [arg for arg in args.arguments if arg != "--"])
    except Interrupted as error:
        return error.status


if __name__ == "__main__":
    sys.exit(main())
