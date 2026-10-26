import importlib.util
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("spotlight_log", pathlib.Path(__file__).with_name("capture-simulator-spotlight-log.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class SpotlightLogTests(unittest.TestCase):
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
