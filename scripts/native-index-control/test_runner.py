import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

SPEC = importlib.util.spec_from_file_location("control_runner", Path(__file__).with_name("runner.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class OwnedDevices:
    def __init__(self, fail=None):
        self.calls = []
        self.fail = fail
        self.next_id = 0

    def run(self, args, stage, **kwargs):
        self.calls.append((stage, args))
        if stage == self.fail:
            raise runner.CommandFailure(stage, 70)
        if stage == "initial-booted" or stage.endswith("remaining-booted"):
            return json.dumps({"devices": {"runtime": [{"udid": "foreign", "state": "Booted"}]}})
        if stage == "available-devices":
            return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"name": "iPhone 17", "deviceTypeIdentifier": "type", "isAvailable": True}
            ]}})
        if stage.endswith("create"):
            self.next_id += 1
            return f"00000000-0000-4000-8000-{self.next_id:012d}"
        return ""


class RunnerTests(unittest.TestCase):
    def test_actual_hosted_device_inventory_prefers_canonical_pro_phone_on_latest_runtime(self):
        inventory = json.loads(Path(__file__).with_name("available-devices-control-38794665933.json").read_text())
        runtime, device = runner.available_device(inventory)
        self.assertEqual(runtime, "com.apple.CoreSimulator.SimRuntime.iOS-26-2")
        self.assertEqual(device["deviceTypeIdentifier"], "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max")

    def test_dispatch_control_is_opt_in_isolated_and_does_not_enter_app_matrix(self):
        workflow = Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml"
        source = workflow.read_text()
        self.assertIn("native_index_control:", source)
        self.assertIn("ci-native-index-control-{0}", source)
        self.assertIn("!inputs.diagnostic_only && !inputs.native_index_control", source)
        app = source.split("  app-ui-tests:", 1)[1]
        self.assertIn("github.event_name != 'workflow_dispatch' || !inputs.native_index_control", app)
        control = source.split("  native-index-control:", 1)[1].split("  app-ui-tests:", 1)[0]
        self.assertIn("needs: dispatch-inputs", control)
        self.assertIn("runs-on: macos-15", control)
        for forbidden in ("rust", "sync-fixture", "run-ui-tests", "Native/", "App/"):
            self.assertNotIn(forbidden, control)

    def test_install_failure_cleans_only_created_device_and_stops_remaining_cells(self):
        commands = OwnedDevices("protected-delete-first.install")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            code = runner.run_cells(commands, output, output / "Control.app", observe=lambda *args: None)
            result = json.loads((output / "result.json").read_text())
        self.assertEqual(code, 70)
        self.assertEqual(result["outcome"], "setup-failed")
        self.assertEqual(commands.next_id, 1)
        stages = [stage for stage, _ in commands.calls]
        self.assertIn("protected-delete-first.shutdown", stages)
        self.assertIn("protected-delete-first.delete", stages)
        self.assertFalse(any("foreign" in args for _, args in commands.calls))
        self.assertNotIn("quit-simulator", stages)

    def test_creation_failure_recovers_only_exact_unique_owned_name_for_cleanup(self):
        commands = OwnedDevices()
        original = commands.run
        owned_name = None

        def run(args, stage, **kwargs):
            nonlocal owned_name
            if stage.endswith(".create"):
                owned_name = args[3]
                raise runner.CommandFailure(stage, 65)
            if stage.endswith(".recover-created"):
                return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                    {"name": owned_name, "udid": "00000000-0000-4000-8000-000000000009"},
                    {"name": "foreign", "udid": "00000000-0000-4000-8000-000000000008"}
                ]}})
            return original(args, stage, **kwargs)

        commands.run = run
        with tempfile.TemporaryDirectory() as directory:
            code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app")
        self.assertEqual(code, 65)
        cleanups = [args for stage, args in commands.calls if stage.endswith((".shutdown", ".delete"))]
        self.assertEqual(len(cleanups), 2)
        self.assertTrue(all(args[-1] == "00000000-0000-4000-8000-000000000009" for args in cleanups))

    def test_conflicting_dispatch_flags_fail_before_control_commands(self):
        source = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
        shell = source.split("          if [[ \"$DIAGNOSTIC_ONLY\"", 1)[1].split("\n\n", 1)[0]
        shell = 'if [[ "$DIAGNOSTIC_ONLY"' + "\n".join(line[10:] if line.startswith("          ") else line for line in shell.splitlines())
        for diagnostic, native, expected in (("false", "false", 0), ("true", "false", 0),
                                              ("false", "true", 0), ("true", "true", 64)):
            result = subprocess.run(["bash", "-c", shell], capture_output=True,
                                    env=dict(os.environ, DIAGNOSTIC_ONLY=diagnostic, NATIVE_INDEX_CONTROL=native))
            self.assertEqual(result.returncode, expected, result.stderr)

    def test_pending_native_cell_continues_four_independent_cells_after_each_cleanup(self):
        commands = OwnedDevices()
        observed = []

        def pending(path, configuration, destination, started):
            observed.append(configuration)
            return {"configuration": configuration, "outcome": "pending", "events": []}

        with tempfile.TemporaryDirectory() as directory:
            code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app", observe=pending)
        self.assertEqual(code, 1)
        self.assertEqual(len(observed), 4)
        self.assertEqual(len({item["token"] for item in observed}), 4)
        stages = [stage for stage, _ in commands.calls]
        for previous, following in zip(runner.CASES, runner.CASES[1:]):
            self.assertLess(stages.index("-".join(previous) + ".delete"),
                            stages.index("-".join(following) + ".create"))

    def test_shutdown_oserror_still_attempts_delete_and_stops_new_cells(self):
        commands = OwnedDevices()
        original = commands.run

        def run(args, stage, **kwargs):
            if stage.endswith(".shutdown"):
                raise OSError("controlled missing tool")
            return original(args, stage, **kwargs)

        commands.run = run
        with tempfile.TemporaryDirectory() as directory:
            code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app",
                                    observe=lambda *args: {"outcome": "pending"})
        self.assertEqual(code, 70)
        self.assertIn("protected-delete-first.delete", [stage for stage, _ in commands.calls])
        self.assertEqual(commands.next_id, 1)

    def test_owned_command_preserves_failure_and_does_not_wait_for_inherited_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = runner.Commands(Path(directory))
            started = time.monotonic()
            child_pid = Path(directory) / "child-pid"
            script = f"import pathlib,subprocess,sys; child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); pathlib.Path({str(child_pid)!r}).write_text(str(child.pid)); print('original bytes',flush=True); sys.exit(65)"
            with self.assertRaises(runner.CommandFailure) as failure:
                commands.run([sys.executable, "-c", script], "inherited-pipe", timeout=5)
            self.assertEqual(failure.exception.code, 65)
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual((Path(directory) / "command-001-inherited-pipe.log").read_text(), "original bytes\n")
            status = subprocess.run(["ps", "-p", child_pid.read_text(), "-o", "stat="], capture_output=True, text=True)
            self.assertTrue(not status.stdout.strip() or status.stdout.strip().startswith("Z"), status.stdout)

    def test_receipt_must_be_regular_bounded_and_match_exact_cell(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = {"token": "owned"}
            raw = root / "receipt.json"
            raw.write_text(json.dumps({"configuration": expected, "outcome": "pending", "events": []}))
            link = root / "link.json"
            link.symlink_to(raw)
            with self.assertRaises(OSError):
                runner.read_receipt(link, expected)
            with self.assertRaises(ValueError):
                runner.read_receipt(raw, {"token": "other"})
            raw.write_bytes(b" " * (runner.MAX_RECEIPT_BYTES + 1))
            with self.assertRaises(ValueError):
                runner.read_receipt(raw, expected)

    def test_all_native_outcomes_keep_api_errors_distinct_from_mismatch_and_pending(self):
        outcomes = iter(["completed", "api-error", "query-mismatch", "pending"])
        commands = OwnedDevices()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            code = runner.run_cells(commands, output, output / "Control.app",
                                    observe=lambda *args: {"outcome": next(outcomes)})
            result = json.loads((output / "result.json").read_text())
        self.assertEqual(code, 1)
        self.assertEqual([cell["outcome"] for cell in result["cells"]],
                         ["completed", "api-error", "query-mismatch", "pending"])

    def test_observation_deadline_preserves_missing_receipt_as_pending(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with patch.object(runner.time, "monotonic", return_value=120):
                result = runner.observe(output / "missing", {"token": "owned"}, output, 0)
        self.assertEqual(result["outcome"], "pending")
        self.assertTrue(result["receiptMissing"])
        self.assertNotIn("error", result)

    def test_native_receipt_rejects_untyped_content_and_huge_numbers(self):
        configuration = {"token": "OWNED", "protection": "protected"}
        receipt = {"configuration": configuration, "pid": 12, "domain": "tsk.native-control.OWNED",
                   "indexName": "tsk.native-control.protected.OWNED", "itemIdentifier": "tsk.native-control.OWNED/item",
                   "outcome": "pending", "events": [{"stage": "index.submit", "time": 1.0,
                                                       "uptime": 1.0, "mainThread": False}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            path.write_text(json.dumps(receipt))
            self.assertEqual(runner.read_receipt(path, configuration), receipt)
            receipt["events"][0]["rawContent"] = "must not pass"
            path.write_text(json.dumps(receipt))
            with self.assertRaises(ValueError):
                runner.read_receipt(path, configuration)
            del receipt["events"][0]["rawContent"]
            receipt["events"][0]["time"] = 10 ** 400
            path.write_text(json.dumps(receipt))
            with self.assertRaises(ValueError):
                runner.read_receipt(path, configuration)

    def test_command_exit_codes_and_output_limit_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = runner.Commands(Path(directory))
            for code in (0, 65, 130, 143, 141):
                invocation = [sys.executable, "-c", f"import sys; sys.exit({code})"]
                if code == 0:
                    self.assertEqual(commands.run(invocation, f"exit-{code}"), "")
                else:
                    with self.assertRaises(runner.CommandFailure) as failure:
                        commands.run(invocation, f"exit-{code}")
                    self.assertEqual(failure.exception.code, code)
            with self.assertRaises(runner.CommandFailure) as failure:
                commands.run([sys.executable, "-c", "import sys; sys.stdout.write('x' * 2000000)"], "too-large")
            self.assertEqual(failure.exception.code, 70)
            self.assertLessEqual((Path(directory) / "command-006-too-large.log").stat().st_size, 1024 * 1024)

    def test_parent_only_signals_reap_exact_owned_command(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum), tempfile.TemporaryDirectory() as directory:
                output = Path(directory)
                owned_pid = output / "owned-pid"
                program = f'''import importlib.util, pathlib, signal, sys
spec = importlib.util.spec_from_file_location("runner", {str(Path(runner.__file__))!r})
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
def stop(signum, frame): raise runner.Interrupted(signum)
signal.signal(signal.SIGINT, stop); signal.signal(signal.SIGTERM, stop)
try:
    runner.Commands(pathlib.Path({directory!r})).run([sys.executable, "-c", {('import os,time,pathlib; pathlib.Path(' + repr(str(owned_pid)) + ').write_text(str(os.getpid())); time.sleep(30)')!r}], "owned")
except runner.Interrupted as error:
    sys.exit(error.code)
'''
                parent = subprocess.Popen([sys.executable, "-c", program])
                try:
                    deadline = time.monotonic() + 3
                    while not owned_pid.exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(owned_pid.exists())
                    pid = int(owned_pid.read_text())
                    parent.send_signal(signum)
                    self.assertEqual(parent.wait(timeout=3), 128 + signum)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
                finally:
                    if parent.poll() is None:
                        parent.kill()
                        parent.wait()

    def test_command_timeout_reaps_child_and_is_not_a_native_callback_error(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            owned_pid = output / "pid"
            program = f"import os,pathlib,time; pathlib.Path({str(owned_pid)!r}).write_text(str(os.getpid())); time.sleep(30)"
            with self.assertRaises(runner.CommandFailure) as failure:
                runner.Commands(output).run([sys.executable, "-c", program], "command-timeout", timeout=0.1)
            self.assertEqual(failure.exception.code, 124)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(owned_pid.read_text()), 0)

    def test_interruption_during_observation_cleans_owned_device_and_keeps_original_status(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            commands = OwnedDevices()

            def interrupted(*args):
                raise runner.Interrupted(signum)

            with tempfile.TemporaryDirectory() as directory:
                code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app", observe=interrupted)
                result = json.loads((Path(directory) / "result.json").read_text())
            self.assertEqual(code, 128 + signum)
            self.assertEqual(result["outcome"], "interrupted")
            self.assertEqual(commands.next_id, 1)
            self.assertEqual([item["stage"] for item in result["cells"][0]["cleanup"]],
                             ["shutdown", "delete", "remaining-booted"])

    def test_parent_signal_during_normal_cleanup_is_preserved_after_all_stages(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            commands = OwnedDevices()
            original = commands.run

            def run(args, stage, **kwargs):
                if stage.endswith(".shutdown"):
                    raise runner.Interrupted(signum)
                return original(args, stage, **kwargs)

            commands.run = run
            with tempfile.TemporaryDirectory() as directory:
                code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app",
                                        observe=lambda *args: {"outcome": "completed"})
                result = json.loads((Path(directory) / "result.json").read_text())
            self.assertEqual(code, 128 + signum)
            self.assertEqual(result["outcome"], "interrupted")
            self.assertEqual(commands.next_id, 1)
            self.assertIn("protected-delete-first.delete", [stage for stage, _ in commands.calls])

    def test_no_installed_runtime_fails_without_creating_any_simulator(self):
        commands = OwnedDevices()
        original = commands.run

        def run(args, stage, **kwargs):
            return '{"devices": {}}' if stage == "available-devices" else original(args, stage, **kwargs)

        commands.run = run
        with tempfile.TemporaryDirectory() as directory:
            code = runner.run_cells(commands, Path(directory), Path(directory) / "Control.app")
        self.assertEqual(code, 70)
        self.assertEqual(commands.next_id, 0)


if __name__ == "__main__":
    unittest.main()
