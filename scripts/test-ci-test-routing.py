#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("ci-test-routing.py")
spec = importlib.util.spec_from_file_location("routing", SCRIPT)
routing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routing)


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "CI routing tests")
        self.git("config", "user.email", "ci@example.invalid")
        self.write("README.md", "Baseline\n")
        self.write("docs/guide.md", "Guide\n")
        self.write("App/Task.swift", "struct Task {}\n")
        self.before = self.commit()

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root, stderr=subprocess.PIPE).decode().strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "--quiet", "--allow-empty", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def event(self, after, name="pull_request", before=None):
        before = before or self.before
        if name == "pull_request":
            return {"pull_request": {"base": {"sha": before}, "head": {"sha": after}}}
        return {"before": before, "after": after}

    def test_documentation_allowlist_keeps_unknown_files_and_fixtures_on_test_path(self):
        for path in ("README.md", "AGENTS.md", "GLOSSARY.md", "LICENSE", "LICENSE.txt", "Native/README.md", "docs/adr/decision.md", "docs/screenshots/example.PNG"):
            with self.subTest(path=path):
                self.assertTrue(routing.documentation_path(path))
        for path in ("App/Task.swift", "Core/Tests/Fixtures/input.md", ".github/workflows/ci.yml", "scripts/check.py", "docs/example.swift", "docs/fixture.json", "unknown.txt"):
            with self.subTest(path=path):
                self.assertFalse(routing.documentation_path(path))

    def test_documentation_only_pull_request_and_push_skip_tests(self):
        self.write("docs/guide.md", "Updated\n")
        self.write("docs/image with\nnewline.png", "fixture")
        after = self.commit()
        for name in ("pull_request", "push"):
            with self.subTest(event=name):
                self.assertFalse(routing.route(name, self.event(after, name), self.root)[0])

    def test_mixed_changes_run_tests(self):
        self.write("README.md", "Updated\n")
        self.write("App/Task.swift", "struct Changed {}\n")
        after = self.commit()
        self.assertTrue(routing.route("pull_request", self.event(after), self.root)[0])

    def test_workflow_changes_run_tests(self):
        self.write(".github/workflows/ci.yml", "name: CI\n")
        after = self.commit()
        self.assertTrue(routing.route("push", self.event(after, "push"), self.root)[0])

    def test_renaming_source_into_documentation_still_runs_tests(self):
        self.git("mv", "App/Task.swift", "docs/example.md")
        after = self.commit()
        self.assertTrue(routing.route("pull_request", self.event(after), self.root)[0])

    def test_deleted_documentation_skips_but_deleted_source_runs(self):
        (self.root / "docs/guide.md").unlink()
        after = self.commit()
        self.assertFalse(routing.route("push", self.event(after, "push"), self.root)[0])
        (self.root / "App/Task.swift").unlink()
        after = self.commit()
        self.assertTrue(routing.route("push", self.event(after, "push"), self.root)[0])

    def test_pull_request_uses_merge_base_and_all_branch_changes(self):
        self.write("README.md", "Branch docs\n")
        head = self.commit()
        self.git("checkout", "--quiet", "-b", "base-advanced", self.before)
        self.write("App/Task.swift", "struct UpstreamChange {}\n")
        base = self.commit()
        self.assertFalse(routing.route("pull_request", self.event(head, before=base), self.root)[0])

    def test_previous_code_commit_is_not_hidden_by_documentation_tip(self):
        self.write("App/Task.swift", "struct Changed {}\n")
        self.commit()
        self.write("README.md", "Docs tip\n")
        after = self.commit()
        self.assertTrue(routing.route("pull_request", self.event(after), self.root)[0])

    def test_manual_scheduled_and_unknown_events_always_run_tests(self):
        for name in ("workflow_dispatch", "schedule", "merge_group", ""):
            with self.subTest(event=name):
                self.assertTrue(routing.route(name, {}, self.root)[0])

    def test_empty_missing_or_invalid_comparison_runs_tests(self):
        events = [{}, None, self.event(self.before), self.event("0" * 40), self.event("f" * 40), self.event("--output=unexpected"), self.event(self.before, before="0" * 40)]
        for event in events:
            with self.subTest(event=event):
                self.assertTrue(routing.route("pull_request", event, self.root)[0])

    def test_cli_outputs_decision_and_summary(self):
        self.write("README.md", "Docs\n")
        event_file = self.root / "event.json"
        after = self.commit()
        event_file.write_text(json.dumps(self.event(after)))
        environment = dict(os.environ, GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event_file), GITHUB_OUTPUT=str(self.root / "output"), GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        subprocess.run(["python3", str(SCRIPT)], cwd=self.root, env=environment, check=True, capture_output=True)
        self.assertEqual((self.root / "output").read_text(), "run_tests=false\n")
        self.assertIn("skipping Core, Native and UI tests", (self.root / "summary").read_text())

    def test_cli_invalid_event_runs_tests(self):
        event_file = self.root / "event.json"
        event_file.write_text("invalid JSON")
        environment = dict(os.environ, GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event_file), GITHUB_OUTPUT=str(self.root / "output"))
        environment.pop("GITHUB_STEP_SUMMARY", None)
        subprocess.run(["python3", str(SCRIPT)], cwd=self.root, env=environment, check=True, capture_output=True)
        self.assertEqual((self.root / "output").read_text(), "run_tests=true\n")


if __name__ == "__main__":
    unittest.main()
