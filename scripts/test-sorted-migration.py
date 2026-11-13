#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from uuid import UUID


SCRIPT = Path(__file__).with_name("migrate-taskwarrior-to-sorted.py")
spec = importlib.util.spec_from_file_location("migration", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


def task(number=1, **fields):
    return {"uuid": str(UUID(int=number)), "description": "A task", "status": "pending", **fields}


def plan(rows, zone="Europe/Paris"):
    raw = json.dumps(rows).encode()
    return migration.plan(rows, zone, hashlib.sha256(raw).hexdigest())


class MigrationTests(unittest.TestCase):
    def test_date_rule_uses_earlier_when_both_exist(self):
        for scheduled, due, field in (("20261115T100000Z", "20261114T110000Z", "due"),
                                      ("20261114T100000Z", "20261115T110000Z", "scheduled"),
                                      ("20261114T100000Z", "20261114T100000Z", "scheduled")):
            with self.subTest(field=field, scheduled=scheduled):
                row = plan([task(scheduled=scheduled, due=due)])["reminders"][0]
                self.assertEqual(row["date_field"], field)
                self.assertEqual(migration.timestamp(row["date"]), min(migration.timestamp(scheduled), migration.timestamp(due)))

    def test_single_date_and_undated_tasks(self):
        for fields, expected in (({}, None), ({"wait": "20261120T000000Z"}, None),
                                 ({"scheduled": "20261113T000000Z"}, "2026-11-13T00:00:00Z"),
                                 ({"due": "20261113T000000Z"}, "2026-11-13T00:00:00Z")):
            with self.subTest(fields=fields):
                self.assertEqual(plan([task(**fields)])["reminders"][0]["date"], expected)

    def test_daylight_saving_uses_calendar_time_zone_and_preserves_midnight(self):
        rows = plan([task(1, scheduled="20261024T220000Z"), task(2, scheduled="20261025T230000Z")])["reminders"]
        self.assertEqual(rows[0]["local_date"], "2026-10-25T00:00:00+02:00")
        self.assertEqual(rows[1]["local_date"], "2026-10-26T00:00:00+01:00")

    def test_iso_offsets_are_compared_as_instants(self):
        row = plan([task(scheduled="2026-11-13T10:00:00+02:00", due="2026-11-13T08:30:00Z")])["reminders"][0]
        self.assertEqual(row["date"], "2026-11-13T08:00:00Z")

    def test_recurring_templates_are_not_duplicated_as_tasks(self):
        template = task(1, status="recurring", recur="monthly", due="20261201T000000Z", mask="-", custom="preserve")
        occurrence = task(2, parent=template["uuid"], recur="monthly", due="20261201T000000Z")
        completed = task(3, status="completed", parent=template["uuid"])
        result = plan([completed, occurrence, template])
        self.assertEqual([r["uuid"] for r in result["reminders"]], [occurrence["uuid"]])
        self.assertEqual(result["manual_series"], [{"source": template, "unfinished_occurrences": [occurrence["uuid"]]}])
        self.assertEqual(result["counts"], {"source": 3, "reminders": 1, "manual_series": 1, "archived": 1})
        self.assertIn("manual setup", result["reminders"][0]["notes"])

    def test_waiting_tasks_are_kept_and_history_stays_out_of_staging(self):
        rows = [task(1, status="waiting"), task(2), task(3, status="completed"), task(4, status="deleted")]
        result = plan(rows)
        self.assertEqual(len(result["reminders"]), 2)
        self.assertEqual(result["counts"]["archived"], 2)

    def test_incomplete_or_ambiguous_recurring_input_is_rejected(self):
        for row in (task(parent=str(UUID(int=2)), recur="daily"), task(recur="daily")):
            with self.subTest(row=row), self.assertRaises(ValueError):
                plan([row])

    def test_ended_series_is_not_restarted(self):
        template = task(1, status="deleted", recur="daily")
        occurrence = task(2, parent=template["uuid"], recur="daily")
        result = plan([template, occurrence])
        self.assertEqual(result["manual_series"], [])
        self.assertIn("No active recurring template", result["reminders"][0]["notes"])

    def test_notes_keep_annotations_and_source_metadata_without_shell_interpretation(self):
        text = "café 🐟\n$(touch /tmp/never) `echo nope` & <script>"
        row = task(description=text, annotations=[{"entry": "20261113T100000Z", "description": text}],
                   project="Work.Team", tags=["café", "research"], priority="H", depends=[str(UUID(int=3))],
                   wait="20261120T000000Z", due="20261114T000000Z", scheduled="20261113T000000Z")
        reminder = plan([row])["reminders"][0]
        self.assertEqual(reminder["title"], text)
        for value in (text, "Project: Work.Team", "Tags: café, research", row["uuid"],
                      "Original Scheduled: 20261113T000000Z", "Original Deadline: 20261114T000000Z", "Waiting until:"):
            self.assertIn(value, reminder["notes"])
        self.assertEqual(reminder["priority"], 1)

    def test_invalid_records_fail_instead_of_silently_dropping_tasks(self):
        bad = [None, {}, task(uuid=None), task(uuid="bad"), task(status="unknown"), task(description=""),
               task(due="2026-11-13"), task(scheduled=123), task(tags="tag"), task(tags=[False]),
               task(project=4), task(annotations=[{"description": 1}]), task(annotations="notes"),
               task(status="recurring")]
        for row in bad:
            with self.subTest(row=row):
                with self.assertRaises((ValueError, KeyError)):
                    plan([row])
        for rows in ({}, [task(), task()]):
            with self.assertRaises(ValueError):
                plan(rows)

    def test_unknown_zone_is_rejected(self):
        with self.assertRaises(KeyError):
            plan([task()], "Unknown/Zone")

    def test_bundle_preserves_exact_source_and_private_permissions(self):
        raw = json.dumps([task(custom={"anything": [1, 2]}, annotations=[])]).encode() + b"\n"
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "bundle"
            result = migration.prepare(raw, output, "Europe/Paris")
            self.assertEqual((output / "source.json").read_bytes(), raw)
            self.assertEqual(result["source_sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(json.loads((output / "source.json").read_bytes())[0]["custom"], {"anything": [1, 2]})
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            self.assertEqual((output / "source.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual((output / "run-mac.sh").stat().st_mode & 0o777, 0o700)
            for name in ("manifest.json", "manual-series.json", "review.md", "stage-reminders.swift", "usage.plist", "README.md"):
                self.assertTrue((output / name).is_file(), name)
            with self.assertRaises(FileExistsError):
                migration.prepare(raw, output, "Europe/Paris")
            self.assertEqual((output / "source.json").read_bytes(), raw)

    def test_invalid_input_creates_no_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "bundle"
            with self.assertRaises(ValueError):
                migration.prepare(b"{}", output, "Europe/Paris")
            self.assertFalse(output.exists())

    def test_partial_bundle_is_removed_on_asset_copy_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "bundle"
            with patch.object(migration.shutil, "copyfile", side_effect=OSError("copy failed")):
                with self.assertRaises(OSError):
                    migration.prepare(json.dumps([task()]).encode(), output, "Europe/Paris")
            self.assertFalse(output.exists())

    def test_cli_does_not_write_personal_data_inside_checkout(self):
        output = SCRIPT.parent / "should-not-exist-personal-bundle"
        result = subprocess.run([sys.executable, str(SCRIPT), "--output", str(output), "--timezone", "Europe/Paris"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the checkout", result.stderr)
        self.assertFalse(output.exists())

    def test_cli_exports_with_generation_and_gc_disabled(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "task"
            executable.write_text("#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n"
                                  "Path(__file__).with_name('arguments.json').write_text(json.dumps(sys.argv[1:]))\n"
                                  "print('[]')\n")
            executable.chmod(0o700)
            result = subprocess.run([sys.executable, str(SCRIPT), "--output", str(root / "bundle"), "--timezone", "Europe/Paris"],
                                    env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((root / "arguments.json").read_text()),
                             ["rc.recurrence=off", "rc.gc=off", "rc.json.array=on", "export"])


@unittest.skipUnless(sys.platform == "darwin", "EventKit helper compilation requires macOS")
class NativePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        cls.bundle = cls.root / "bundle"
        raw = json.dumps([task()]).encode()
        cls.manifest = migration.prepare(raw, cls.bundle, "Europe/Paris")
        compiled = subprocess.run(["/bin/bash", str(cls.bundle / "run-mac.sh"), "validate"], capture_output=True, text=True)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)

    def test_offline_native_checks_never_request_reminders_access(self):
        original = self.manifest
        duplicate = {**original, "reminders": original["reminders"] + original["reminders"]}
        malformed = {**original, "reminders": [{**original["reminders"][0], "date": "not-a-date"}]}
        cases = [
            (original, "validate", 0, "Validated 1 unfinished tasks", False, False),
            (original, "validate", 1, "checksum", True, False),
            (duplicate, "validate", 1, "Duplicate source UUIDs", False, False),
            ({**original, "timezone": "Unknown/Zone"}, "validate", 1, "Unsupported manifest or time zone", False, False),
            (malformed, "validate", 1, "Invalid migration date", False, False),
            (original, "apply", 1, "Run sample", False, False),
            (original, "apply", 1, "manifest changed", False, True),
        ]
        for manifest, mode, code, phrase, corrupt_source, stale_receipt in cases:
            with self.subTest(mode=mode, phrase=phrase), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "manifest.json").write_text(json.dumps(manifest))
                raw = (self.bundle / "source.json").read_bytes() + (b"\n" if corrupt_source else b"")
                (root / "source.json").write_bytes(raw)
                if stale_receipt:
                    (root / "receipt-sample.json").write_text(json.dumps({"manifestSHA256": "different", "calendarID": "test", "saved": {}}))
                command = [str(self.bundle / ".stage-reminders"), str(root / "manifest.json"), mode]
                if mode == "apply":
                    command.append("--sample-checked")
                result = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn(phrase, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
