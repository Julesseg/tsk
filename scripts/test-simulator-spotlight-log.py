import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("spotlight_log", pathlib.Path(__file__).with_name("capture-simulator-spotlight-log.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class SpotlightLogTests(unittest.TestCase):
    def test_long_method_capture_stops_and_reaps_at_test_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport signal,sys,time\nsignal.signal(signal.SIGTERM,lambda *_:sys.exit(143))\nprint('ready',flush=True)\nwhile True:time.sleep(.01)\n")
            tool.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
            process = subprocess.Popen([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--maximum-seconds", "600"], env=environment)
            try:
                deadline = time.monotonic() + 2
                while not (root / "stream.log").exists() or not (root / "stream.log").read_text():
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(.01)
                (root / "stop").touch()
                self.assertEqual(process.wait(timeout=2), 0)
                metadata = json.loads((root / "stream.metadata.json").read_text())
                self.assertEqual(metadata["stoppedBy"], "test-completion")
                self.assertEqual(metadata["returnCode"], 143)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=7)

    def test_cli_accepts_a_method_window_without_changing_the_test_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport sys\nprint(sys.argv[sys.argv.index('--timeout')+1],flush=True)\n")
            tool.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
            subprocess.run([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--maximum-seconds", "600"], env=environment, check=True, timeout=2)
            self.assertEqual((root / "stream.log").read_text().strip(), "600")
            metadata = json.loads((root / "stream.metadata.json").read_text())
            self.assertEqual(metadata["maximumSeconds"], 600)
            self.assertEqual(metadata["returnCode"], 0)

    def test_duration_expires_in_guest_without_a_host_termination_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport signal,sys,time\nsignal.signal(signal.SIGTERM, lambda *_: sys.exit(143))\nif '--timeout' in sys.argv:\n time.sleep(.05)\n sys.exit(0)\nwhile True: time.sleep(.01)\n")
            tool.chmod(0o700)
            with patch.dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", "")):
                result = capture.capture("owned-device", root / "stream.log", root / "stop", maximum_seconds=.1)
            self.assertEqual(result["returnCode"], 0)
            command = result["command"]
            self.assertEqual(command[command.index("--timeout") + 1], "1")


if __name__ == "__main__":
    unittest.main()
