#!/usr/bin/env python3
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from uuid import UUID
from zoneinfo import ZoneInfo


ASSETS = Path(__file__).with_name("sorted-migration")
ACTIVE = {"pending", "waiting"}
STATUSES = ACTIVE | {"recurring", "completed", "deleted"}


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("Task dates must be strings")
    try:
        parsed = datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError(f"Task date has no time zone: {value}")
    return parsed.astimezone(timezone.utc)


def validate(rows):
    if not isinstance(rows, list):
        raise ValueError("Expected a Taskwarrior JSON array")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("Every task must be an object")
        if not isinstance(row.get("uuid"), str):
            raise ValueError("Every task must have a UUID string")
        identifier = str(UUID(row["uuid"]))
        if row["uuid"] != identifier or identifier in seen:
            raise ValueError(f"Duplicate or noncanonical task UUID: {identifier}")
        seen.add(identifier)
        if row.get("status") not in STATUSES:
            raise ValueError(f"Unknown status on task {identifier}: {row.get('status')}")
        if not isinstance(row.get("description"), str) or not row["description"].strip():
            raise ValueError(f"Task {identifier} has no description")
        for field in ("scheduled", "due", "wait", "until"):
            if row.get(field):
                timestamp(row[field])
        for field in ("project", "priority", "parent", "recur", "rtype"):
            if field in row and not isinstance(row[field], str):
                raise ValueError(f"Task {identifier}: {field} must be text")
        if "tags" in row and (not isinstance(row["tags"], list) or
                              any(not isinstance(tag, str) for tag in row["tags"])):
            raise ValueError(f"Task {identifier}: tags must be a list of strings")
        if "annotations" in row:
            if not isinstance(row["annotations"], list):
                raise ValueError(f"Task {identifier}: annotations must be a list")
            for annotation in row["annotations"]:
                if not isinstance(annotation, dict) or not isinstance(annotation.get("description"), str):
                    raise ValueError(f"Task {identifier}: invalid annotation")
        if row.get("status") == "recurring" and not row.get("recur"):
            raise ValueError(f"Recurring template {identifier} has no repeat rule")
    for row in rows:
        if row["status"] not in ACTIVE:
            continue
        if row.get("parent") and row["parent"] not in seen:
            raise ValueError(f"Task {row['uuid']} references a missing recurring template; provide a full export")
        if row.get("recur") and not row.get("parent"):
            raise ValueError(f"Task {row['uuid']} has an ambiguous repeat rule without a template relationship")


def task_date(row):
    dates = [(timestamp(row[key]), key) for key in ("scheduled", "due") if row.get(key)]
    if not dates:
        return None, None
    value, field = min(dates, key=lambda item: item[0])
    return value.isoformat(timespec="seconds").replace("+00:00", "Z"), field


def notes(row, templates):
    paragraphs = [annotation["description"] for annotation in row.get("annotations", [])]
    metadata = [f"Taskwarrior UUID: {row['uuid']}"]
    for field, label in (("project", "Project"), ("priority", "Priority"),
                         ("scheduled", "Original Scheduled"), ("due", "Original Deadline"),
                         ("wait", "Waiting until"), ("depends", "Dependencies"),
                         ("start", "Started")):
        if row.get(field):
            metadata.append(f"{label}: {row[field]}")
    if row.get("tags"):
        metadata.append("Tags: " + ", ".join(row["tags"]))
    if row.get("parent") or row.get("recur"):
        template = templates.get(row.get("parent"), row)
        metadata.append(f"Recurring series: {row.get('parent', row['uuid'])}")
        metadata.append(f"Original repeat: {template.get('recur', row.get('recur', 'unknown'))}")
        if row.get("parent") in templates:
            metadata.append("Repeat rule needs manual setup in Sorted; this is a single occurrence.")
        else:
            metadata.append("No active recurring template in the export; this remains a single occurrence.")
    paragraphs.append("\n".join(metadata))
    return "\n\n".join(paragraphs)


def plan(rows, zone_name, source_hash):
    validate(rows)
    zone = ZoneInfo(zone_name)
    templates = {row["uuid"]: row for row in rows if row["status"] == "recurring"}
    tasks = []
    for row in rows:
        if row["status"] not in ACTIVE:
            continue
        date, date_field = task_date(row)
        tasks.append({
            "uuid": row["uuid"], "title": row["description"],
            "date": date, "date_field": date_field,
            "local_date": timestamp(date).astimezone(zone).isoformat() if date else None,
            "notes": notes(row, templates), "project": row.get("project"),
            "annotations": row.get("annotations", []),
            "tags": row.get("tags", []),
            "priority": {"H": 1, "M": 5, "L": 9}.get(row.get("priority"), 0),
            "source_url": "tsk-sorted-migration://task/" + row["uuid"],
        })
    tasks.sort(key=lambda row: row["uuid"])
    series = []
    for identifier, template in sorted(templates.items()):
        occurrences = [row["uuid"] for row in rows if row["status"] in ACTIVE and row.get("parent") == identifier]
        series.append({"source": template, "unfinished_occurrences": sorted(occurrences)})
    return {
        "version": 2, "source_sha256": source_hash, "timezone": zone_name,
        "counts": {"source": len(rows), "tasks": len(tasks),
                   "manual_series": len(series),
                   "archived": sum(row["status"] in {"completed", "deleted"} for row in rows)},
        "source_statuses": dict(Counter(row["status"] for row in rows)),
        "tasks": tasks, "manual_series": series,
    }


def report(manifest):
    counts = manifest["counts"]
    lines = ["# Sorted migration preview", "",
             f"Source SHA-256: `{manifest['source_sha256']}`", "",
             f"Time zone: {manifest['timezone']}", "",
             f"- {counts['source']} source records preserved in source.json.",
             f"- {counts['tasks']} unfinished tasks ready for direct import.",
             f"- {counts['manual_series']} recurring series require manual setup in Sorted.",
             f"- {counts['archived']} completed/deleted records retained only in the archive.", "",
             "## Transfer boundaries", "",
             "Date = the earlier of Scheduled and Deadline, or the sole date. Undated tasks stay undated. "
             "Dates retain their time in the selected time zone, including midnight.", "",
             "Tasks go directly to Sorted using its Add URL, with project mapped to list and tags passed through. "
             "The documented URL has no notes, priority, waiting/dependency or repeat-rule inputs. "
             "Those fields remain in source.json, with actionable exceptions in manual-work.md. "
             "Dates use minute precision because that is what Sorted's documented URL accepts.", "",
             "A successful URL dispatch means macOS accepted the request; it is not an acknowledgement of "
             "durable saving inside Sorted. The local receipt records requests sent and protects retries, "
             "but cannot detect tasks independently removed from Sorted.", "",
             "## Recurring series", "",
             "All unfinished generated occurrences are sent as individual tasks. For each series, "
             "configure repetition on the appropriate imported occurrence in Sorted and verify its next dates. "
             "Keep other outstanding occurrences as single tasks. Do not import the template as another "
             "ordinary task. If there is no unfinished occurrence, create and check the next occurrence manually. "
             "Original series fields and occurrence identities are in manual-series.json.", ""]
    for series in manifest["manual_series"]:
        row = series["source"]
        lines.extend([f"- {row['description']!r}: `{row['recur']}`; template `{row['uuid']}`; "
                      f"unfinished occurrences: {', '.join(series['unfinished_occurrences']) or 'none'}."])
    lines.extend(["", "## Tasks", ""])
    for row in manifest["tasks"]:
        lines.append(f"- `{row['uuid']}` {row['title']!r} — "
                     f"{row['local_date'] or 'undated'}; project {row['project']!r}.")
    return "\n".join(lines) + "\n"


def manual_work(manifest, rows):
    annotated = [row for row in rows if row["status"] in ACTIVE and row.get("annotations")]
    fields = [row for row in rows if row["status"] in ACTIVE and any(row.get(key) for key in ("priority", "wait", "depends"))]
    lines = ["# Fields Sorted's Add URL cannot transfer", "",
             "The full original data is preserved in source.json. Tasks, lists, tags and dates are sent automatically.", "",
             f"## Notes to copy ({len(annotated)} tasks)", ""]
    for row in annotated:
        lines.extend([f"### {row['description']}", f"Source: {row['uuid']}", ""])
        for annotation in row["annotations"]:
            lines.extend([annotation["description"], ""])
    lines.extend([f"## Repeat rules to set ({len(manifest['manual_series'])} series)", "",
                  "Set the rule on the appropriate imported occurrence; keep other outstanding occurrences as single tasks. "
                  "Original rule fields and occurrence IDs are in manual-series.json.", ""])
    for series in manifest["manual_series"]:
        row = series["source"]
        lines.extend([f"- {row['description']!r}: {row['recur']}; until {row.get('until', 'no end')}; "
                      f"occurrences {', '.join(series['unfinished_occurrences']) or 'none; create the next task manually'}."])
    lines.extend(["", f"## Other source fields ({len(fields)} tasks)", ""])
    for row in fields:
        values = {key: row[key] for key in ("priority", "wait", "depends") if row.get(key)}
        lines.append(f"- {row['description']!r}: {json.dumps(values, ensure_ascii=False)}")
    ambiguous_tags = [row for row in rows if row["status"] in ACTIVE and any("," in tag for tag in row.get("tags", []))]
    if ambiguous_tags:
        lines.extend(["", "## Tags containing commas", "",
                      "These tasks omit automatic tags because Sorted uses a comma-separated tag parameter:", ""])
        for row in ambiguous_tags:
            lines.append(f"- {row['description']!r}: {row['tags']!r}")
    return "\n".join(lines) + "\n"


def prepare(raw, output, zone_name):
    rows = json.loads(raw)
    manifest = plan(rows, zone_name, hashlib.sha256(raw).hexdigest())
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    try:
        (output / "source.json").write_bytes(raw)
        for name, content in (("manifest.json", manifest), ("manual-series.json", manifest["manual_series"])):
            (output / name).write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n")
        (output / "review.md").write_text(report(manifest))
        (output / "manual-work.md").write_text(manual_work(manifest, rows))
        for asset in ASSETS.iterdir():
            if asset.is_file():
                shutil.copyfile(asset, output / asset.name)
        for path in output.iterdir():
            path.chmod(0o700 if path.name == "run-mac.sh" else 0o600)
    except BaseException:
        shutil.rmtree(output)
        raise
    return manifest


def main():
    parser = argparse.ArgumentParser(description="Prepare a private, one-command Taskwarrior → Sorted migration bundle.")
    parser.add_argument("--input", type=Path, help="Full Taskwarrior JSON export; omit to export the local database without recurrence generation or garbage collection")
    parser.add_argument("--output", type=Path, required=True, help="New private output directory, outside the checkout")
    parser.add_argument("--timezone", required=True, help="IANA time zone, e.g. Europe/Paris")
    args = parser.parse_args()
    try:
        output = args.output.expanduser().resolve()
        checkout = Path(__file__).resolve().parents[1]
        if output == checkout or checkout in output.parents:
            raise ValueError("Choose an output directory outside the checkout to keep personal tasks out of Git")
        if output.exists():
            raise ValueError("Output directory already exists; reuse that bundle or choose a new directory")
        ZoneInfo(args.timezone)
        if args.input:
            raw = args.input.expanduser().read_bytes()
        else:
            result = subprocess.run(["task", "rc.recurrence=off", "rc.gc=off", "rc.json.array=on", "export"],
                                    check=True, capture_output=True)
            raw = result.stdout
        os.umask(0o077)
        manifest = prepare(raw, output, args.timezone)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Migration preparation failed: {error}\n")
    print(json.dumps({"bundle": str(output), **manifest["counts"]}, indent=2))
    print("On the Mac, run ./run-mac.sh to send the tasks directly to Sorted.")
    if manifest["manual_series"]:
        print("Notes and repeat-rule exceptions are in manual-work.md.")


if __name__ == "__main__":
    main()
