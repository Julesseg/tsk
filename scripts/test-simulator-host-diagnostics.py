import importlib.util
import json
import pathlib
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).with_name("with-simulator-host-diagnostics.py")
spec = importlib.util.spec_from_file_location("host_diagnostics", SCRIPT)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)
POPEN = subprocess.Popen


class HostDiagnosticsTests(unittest.TestCase):
    def test_captures_legacy_service_events_after_command_start(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory)
            source = output / "source.log"
            source.write_text("older unrelated event\n")
            cursor = diagnostics.service_log_cursor(source)
            with source.open("a") as file:
                file.write("shutdown requester 123\n")
            diagnostics.capture_service_log(source, output, cursor)
            self.assertEqual((output / "core-simulator-service.log").read_text(), "shutdown requester 123\n")

    def test_preserves_new_service_log_after_rotation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory)
            source = output / "source.log"
            source.write_text("previous service\n")
            cursor = diagnostics.service_log_cursor(source)
            source.rename(output / "source.log.1")
            source.write_text("restarted service\n")
            diagnostics.capture_service_log(source, output, cursor)
            self.assertEqual((output / "core-simulator-service.log").read_text(), "restarted service\n")

    def execute(self, status, logger_status=None):
        processes = []

        def start(command, **kwargs):
            if command[0] == "/usr/bin/log":
                command = [sys.executable, "-c", "import time; time.sleep(60)" if logger_status is None else f"raise SystemExit({logger_status})"]
            process = POPEN(command, **kwargs)
            processes.append(process)
            return process

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory)
            with patch.object(diagnostics.subprocess, "Popen", side_effect=start), patch.object(diagnostics, "sample"):
                result = diagnostics.run([sys.executable, "-c", f"import time; time.sleep(.3); raise SystemExit({status})"], output)
            receipt = json.loads((output / "receipt.json").read_text())
        self.assertTrue(all(process.poll() is not None for process in processes))
        self.assertEqual(result, status)
        self.assertEqual(receipt["status"], status)
        return receipt

    def test_preserves_failed_ui_command_and_reaps_owned_logger(self):
        receipt = self.execute(65)
        self.assertEqual(receipt["logStatus"], -signal.SIGTERM)

    def test_preserves_success_and_reaps_owned_logger(self):
        self.execute(0)

    def test_diagnostic_process_failure_cannot_turn_failed_ui_green(self):
        receipt = self.execute(70, logger_status=2)
        self.assertEqual(receipt["logStatus"], 2)


if __name__ == "__main__":
    unittest.main()
