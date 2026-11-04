#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("agent_dispatch", Path(__file__).with_name("start-agent-thread.py"))
dispatch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatch)


class AgentDispatchTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="tsk dispatch ")
        self.addCleanup(self.directory.cleanup)
        self.env = {
            "ISSUE": "42", "T3_PROJECT_DIR": self.directory.name,
            "T3_CLI": "/tools/t3",
        }

    @patch.object(dispatch.subprocess, "run")
    def test_checks_server_then_fetches_then_starts_isolated_thread(self, run):
        dispatch.start(self.env)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ["/tools/t3", "thread", "list", "--project", self.directory.name, "--json"])
        self.assertEqual(commands[1], ["git", "-C", self.directory.name, "fetch", "--prune", "origin"])
        launch = commands[2]
        self.assertEqual(launch[:4], ["/tools/t3", "thread", "start", self.directory.name])
        self.assertIn("issue #42", launch[4])
        self.assertIn("docs/agents/t3-code.md", launch[4])
        self.assertEqual(launch[5:], [
            "--title", "Implement issue #42",
            "--worktree", "origin/main", "--branch", "agent/issue-42", "--json",
        ])

    @patch.object(dispatch.subprocess, "run")
    def test_custom_base_and_server_home_apply_to_both_cli_calls(self, run):
        dispatch.start({**self.env, "T3_BASE": "origin/release", "T3_BASE_DIR": "/custom t3"})
        commands = [call.args[0] for call in run.call_args_list]
        for command in (commands[0], commands[2]):
            self.assertEqual(command[-2:], ["--base-dir", "/custom t3"])
        self.assertEqual(commands[2][commands[2].index("--worktree") + 1], "origin/release")

    @patch.object(dispatch.subprocess, "run")
    def test_missing_configuration_starts_nothing(self, run):
        for key in ("T3_PROJECT_DIR",):
            with self.subTest(key=key), self.assertRaises(ValueError):
                dispatch.start({**self.env, key: ""})
        run.assert_not_called()

    @patch.object(dispatch.subprocess, "run")
    def test_invalid_issue_starts_nothing(self, run):
        for issue in ("", "0", "-1", "42; touch /tmp/unwanted", "1\n2"):
            with self.subTest(issue=issue), self.assertRaises(ValueError):
                dispatch.start({**self.env, "ISSUE": issue})
        run.assert_not_called()

    @patch.object(dispatch.subprocess, "run")
    def test_invalid_checkout_starts_nothing(self, run):
        for project in ("relative", str(Path(self.directory.name) / "absent")):
            with self.subTest(project=project), self.assertRaises(ValueError):
                dispatch.start({**self.env, "T3_PROJECT_DIR": project})
        run.assert_not_called()

    @patch.object(dispatch.subprocess, "run")
    def test_unavailable_server_prevents_fetch_and_launch(self, run):
        run.side_effect = subprocess.CalledProcessError(1, "t3", stderr="server offline")
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 1)

    @patch.object(dispatch.subprocess, "run")
    def test_fetch_failure_prevents_launch(self, run):
        run.side_effect = [None, subprocess.CalledProcessError(1, "git")]
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 2)

    @patch.object(dispatch.subprocess, "run")
    def test_launch_failure_is_not_retried(self, run):
        run.side_effect = [None, None, subprocess.CalledProcessError(1, "t3")]
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 3)


if __name__ == "__main__":
    unittest.main()
