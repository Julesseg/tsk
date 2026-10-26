#!/usr/bin/env python3
import argparse
import datetime
import json
import pathlib
import shutil
import signal
import subprocess
import time


PREDICATE = '(process CONTAINS "CoreSimulatorService" OR process == "simdiskimaged" OR process == "Simulator" OR process == "DeviceHub" OR process == "launchd_sim" OR subsystem BEGINSWITH "com.apple.CoreSimulator") OR (process == "kernel" AND (eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "memory pressure"))'


def service_log_cursor(source):
    try:
        state = source.stat()
        return state.st_ino, state.st_size
    except FileNotFoundError:
        return None, 0


def capture_service_log(source, output, cursor):
    with source.open("rb") as file:
        state = source.stat()
        offset = cursor[1] if state.st_ino == cursor[0] and state.st_size >= cursor[1] else 0
        offset = max(offset, state.st_size - 16 * 1024 * 1024)
        file.seek(offset)
        with (output / "core-simulator-service.log").open("wb") as destination:
            shutil.copyfileobj(file, destination)
    return {"source": str(source), "offset": offset, "bytes": state.st_size - offset}


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sample(output):
    commands = [
        ["/usr/bin/vm_stat"],
        ["/usr/sbin/sysctl", "vm.swapusage"],
        ["/bin/df", "-k", str(output)],
        ["/bin/ps", "-A", "-o", "pid,ppid,rss,comm"],
    ]
    record = {"timeUTC": utc(), "commands": []}
    for command in commands:
        entry = {"command": command}
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=3)
            entry.update(status=result.returncode, stdout=result.stdout, stderr=result.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            entry["error"] = str(error)
        record["commands"].append(entry)
    with (output / "resources.jsonl").open("a") as file:
        file.write(json.dumps(record) + "\n")


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def run(command, output):
    output.mkdir(parents=True, exist_ok=True)
    receipt = {"startedUTC": utc(), "events": []}
    child = None
    logger = None
    interrupted = None
    handlers = {}
    service_log = pathlib.Path.home() / "Library/Logs/CoreSimulator/CoreSimulator.log"
    cursor = service_log_cursor(service_log)

    def interrupt(number, _frame):
        nonlocal interrupted
        interrupted = number
        if child is not None and child.poll() is None:
            child.send_signal(number)

    for number in (signal.SIGINT, signal.SIGTERM):
        handlers[number] = signal.signal(number, interrupt)
    try:
        with (output / "core-simulator.log").open("wb") as log:
            try:
                logger = subprocess.Popen(["/usr/bin/log", "stream", "--style", "compact", "--level", "debug", "--predicate", PREDICATE], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                receipt["logPID"] = logger.pid
            except OSError as error:
                receipt["logError"] = str(error)
            child = subprocess.Popen(command)
            receipt["commandPID"] = child.pid
            next_sample = 0
            while child.poll() is None:
                if interrupted is not None:
                    try:
                        child.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        stop(child)
                    break
                if time.monotonic() >= next_sample:
                    try:
                        sample(output)
                    except OSError as error:
                        receipt["events"].append({"timeUTC": utc(), "sampleError": str(error)})
                    next_sample = time.monotonic() + 15
                if logger is not None and logger.poll() is None and log.tell() >= 64 * 1024 * 1024:
                    receipt["events"].append({"timeUTC": utc(), "logLimitBytes": log.tell()})
                    stop(logger)
                time.sleep(0.2)
            status = 128 + interrupted if interrupted is not None else child.returncode
            receipt["status"] = status if status >= 0 else 128 - status
    finally:
        if child is not None:
            stop(child)
        if logger is not None:
            stop(logger)
            receipt["logStatus"] = logger.returncode
        receipt["finishedUTC"] = utc()
        try:
            receipt["serviceLog"] = capture_service_log(service_log, output, cursor)
        except OSError as error:
            receipt["serviceLogError"] = str(error)
        for number, handler in handlers.items():
            signal.signal(number, handler)
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt["status"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("Pass the UI command after --")
    raise SystemExit(run(command, args.output))
