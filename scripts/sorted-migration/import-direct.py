#!/usr/bin/env python3
import argparse
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import quote, urlencode
from uuid import UUID
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent


def load_bundle(directory):
    raw = (directory / "manifest.json").read_bytes()
    manifest = json.loads(raw)
    source = (directory / "source.json").read_bytes()
    if manifest.get("version") != 2 or hashlib.sha256(source).hexdigest() != manifest.get("source_sha256"):
        raise ValueError("The migration bundle is incomplete or its source checksum changed")
    ZoneInfo(manifest["timezone"])
    seen = set()
    for task in manifest["tasks"]:
        identifier = str(UUID(task["uuid"]))
        if identifier != task["uuid"] or identifier in seen:
            raise ValueError("Invalid or duplicate task identity in the bundle")
        seen.add(identifier)
        if not isinstance(task["title"], str) or not task["title"].strip():
            raise ValueError("Every task must have a title")
        if task.get("date"):
            date = datetime.fromisoformat(task["date"].replace("Z", "+00:00"))
            if date.tzinfo is None:
                raise ValueError("A migration date has no time zone")
        if task.get("project") is not None and not isinstance(task["project"], str):
            raise ValueError("Project names must be text")
        if not isinstance(task["tags"], list) or any(not isinstance(tag, str) for tag in task["tags"]):
            raise ValueError("Task tags must be a list of strings")
    return manifest, hashlib.sha256(raw).hexdigest()


def task_url(task, zone_name):
    parameters = {"title": task["title"], "type": "task", "earlyAlert": "none"}
    if task.get("date"):
        date = datetime.fromisoformat(task["date"].replace("Z", "+00:00"))
        parameters["date"] = date.astimezone(ZoneInfo(zone_name)).strftime("%Y-%m-%d %H:%M")
    if task.get("project"):
        parameters["list"] = task["project"]
    if task.get("tags") and not any("," in tag for tag in task["tags"]):
        parameters["tags"] = ",".join(task["tags"])
    return "sorted://x-callback-url/add?" + urlencode(parameters, quote_via=quote)


def save_state(path, state):
    temporary = path.with_suffix(".tmp")
    try:
        with temporary.open("w", encoding="utf-8") as output:
            json.dump(state, output, ensure_ascii=False, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        temporary.chmod(0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def dispatch(directory, manifest, fingerprint, opener=subprocess.run, sleep=time.sleep, delay=1.0, resolve=None):
    path = directory / "import-state.json"
    if any((directory / name).exists() for name in ("receipt.json", "receipt-sample.json")):
        raise ValueError("This bundle already used the Reminders route; reconcile that transfer before using direct import")
    state = json.loads(path.read_bytes()) if path.exists() else {
        "manifest_sha256": fingerprint, "dispatched": [], "pending": None,
    }
    if state.get("manifest_sha256") != fingerprint:
        raise ValueError("The bundle changed after import started; use its original manifest")
    identifiers = {task["uuid"] for task in manifest["tasks"]}
    sent = state.get("dispatched")
    if not isinstance(sent, list) or len(sent) != len(set(sent)) or not set(sent) <= identifiers:
        raise ValueError("The import receipt has invalid task identities")
    pending = state.get("pending")
    if pending and pending not in identifiers:
        raise ValueError("The import receipt has an invalid pending task")
    if pending:
        if resolve == "sent":
            if pending not in sent:
                sent.append(pending)
        elif resolve != "retry":
            raise ValueError(f"An interrupted request may already be in Sorted ({pending}). Check it, then rerun with --resolve-pending sent or --resolve-pending retry")
        state["pending"] = None
        save_state(path, state)
    remaining = [task for task in manifest["tasks"] if task["uuid"] not in set(sent)]
    if not remaining:
        print(f"All {len(sent)} task requests were already sent; nothing repeated.")
        return
    urls = [(task["uuid"], task_url(task, manifest["timezone"])) for task in remaining]
    opener(["/usr/bin/open", "-a", "Sorted³"], check=True)
    sleep(2.0)
    print(f"Sending {len(urls)} tasks directly to Sorted…", flush=True)
    for identifier, url in urls:
        state["pending"] = identifier
        save_state(path, state)
        opener(["/usr/bin/open", "-g", url], check=True)
        sent.append(identifier)
        state["pending"] = None
        save_state(path, state)
        sleep(delay)
    print(f"Sent {len(urls)} task requests. Source tasks were left untouched.")
    print("Notes and repeat rules needing attention are in manual-work.md.")
    print("The receipt tracks URL dispatch; Sorted does not provide a save acknowledgement through this interface.")


def main():
    parser = argparse.ArgumentParser(description="Send the prepared task bundle directly to Sorted. No Reminders or permission setup.")
    parser.add_argument("--dry-run", action="store_true", help="Validate without opening Sorted")
    parser.add_argument("--resolve-pending", choices=("sent", "retry"), help="Resolve an interrupted request after checking that task in Sorted")
    args = parser.parse_args()
    try:
        os.umask(0o077)
        manifest, fingerprint = load_bundle(ROOT)
        if args.dry_run:
            for task in manifest["tasks"]:
                task_url(task, manifest["timezone"])
            print(f"Ready: {len(manifest['tasks'])} tasks, direct to Sorted. No apps opened.")
            return
        if sys.platform != "darwin":
            raise ValueError("Run run-mac.sh on your Mac")
        with (ROOT / ".import-lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError("This bundle is already importing in another process")
            dispatch(ROOT, manifest, fingerprint, resolve=args.resolve_pending)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Import stopped: {error}\n")


if __name__ == "__main__":
    main()
