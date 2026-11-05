import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys
import tarfile
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[1]


def select_host(explicit, settings):
    if explicit:
        host = {"target": explicit}
    else:
        hosts = [host for host in settings.get("deviceHosts", []) if host.get("kind") == "ssh"]
        if len(hosts) != 1:
            raise ValueError("Set TSK_REMOTE_HOST or --host, or configure exactly one SSH source in T3 Settings → Devices.")
        host = hosts[0]
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.@-]*", host["target"]):
        raise ValueError("Use an SSH alias or user@hostname for the remote Mac.")
    return host


def ssh_options(host):
    options = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
               "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3"]
    if host.get("port"):
        port = int(host["port"])
        if not 1 <= port <= 65535:
            raise ValueError("SSH port must be between 1 and 65535.")
        options += ["-o", f"Port={port}"]
    if host.get("identityFile"):
        options += ["-i", str(Path(host["identityFile"]).expanduser())]
    return options


def write_snapshot(root, output):
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root)
    with tarfile.open(fileobj=output, mode="w:gz", dereference=True) as archive:
        for name in sorted(set(os.fsdecode(name) for name in files.split(b"\0") if name)):
            relative = Path(name)
            if any(part == ".git" or part == ".env" or part.startswith(".env.") for part in relative.parts):
                continue
            path = root / relative
            if not path.exists():
                continue
            if not path.resolve().is_relative_to(root):
                raise ValueError(f"Source link leaves this checkout: {name}")
            if not path.is_file():
                raise ValueError(f"Expected a source file: {name}")
            archive.add(path, arcname=name, recursive=False)
    output.seek(0)


def main():
    parser = argparse.ArgumentParser(description="Sync this checkout to an isolated Mac cache and run iOS development commands.")
    parser.add_argument("action", choices=["doctor", "sync", "build", "core", "native", "install", "test"])
    parser.add_argument("--host", default=os.environ.get("TSK_REMOTE_HOST"))
    parser.add_argument("--device", help="Simulator UDID on the selected SSH host")
    parser.add_argument("--only", action="append", default=[], help="Focused XCUITest identifier; repeat to select several tests")
    args = parser.parse_args()
    if args.action in ["install", "test"]:
        if not args.device:
            parser.error("--device is required; discover the host and device with T3 device_list first")
        try:
            uuid.UUID(args.device)
        except ValueError:
            parser.error("--device must be a simulator UDID")
    if args.action == "test" and not args.only:
        parser.error("test requires at least one --only TskUITests/Class[/method]; full coverage runs in CI")
    if any(not re.fullmatch(r"TskUITests/[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?", value) for value in args.only):
        parser.error("--only must be TskUITests/Class[/method]")
    settings_path = Path(os.environ.get("T3CODE_HOME", str(Path.home() / ".t3"))) / "userdata/settings.json"
    settings = json.loads(settings_path.read_text()) if settings_path.exists() and not args.host else {}
    host = select_host(args.host, settings)
    options = ssh_options(host)
    key = hashlib.sha256((socket.gethostname() + "\0" + str(ROOT)).encode()).hexdigest()[:20]
    run_id = uuid.uuid4().hex
    request = {"key": key, "action": args.action, "device": args.device, "only": args.only, "run": run_id}
    worker = (ROOT / "scripts/remote-ios-worker.py").read_text()
    command = ["ssh", "-T", *options, host["target"], shlex.join(["/usr/bin/python3", "-c", worker, json.dumps(request)])]
    print(f"Remote Mac: {host['target']}\nWorkspace: ~/Library/Caches/tsk-remote/{key}", flush=True)
    with tempfile.TemporaryFile() as snapshot:
        write_snapshot(ROOT, snapshot)
        result = subprocess.run(command, stdin=snapshot)
    if args.action == "test":
        destination = ROOT / ".build/remote-ios" / run_id
        destination.mkdir(parents=True, exist_ok=True)
        source = f"{host['target']}:Library/Caches/tsk-remote/{key}/results/{run_id}/."
        receipt = subprocess.run(["scp", "-r", *options, source, str(destination)])
        print(f"Local test results: {destination}", flush=True)
        if receipt.returncode and not result.returncode:
            return receipt.returncode
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"remote-ios: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
