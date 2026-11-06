import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).with_name("run-ui-tests.sh")


class UITestLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.helper = self.home / ".config/bin/simulator-lease"
        self.helper.parent.mkdir(parents=True)
        self.log = self.home / "calls.json"
        self.helper.write_text(
            "#!/usr/bin/env python3\nimport json,os,pathlib,sys\n"
            "pathlib.Path(os.environ['LEASE_CALL_LOG']).write_text(json.dumps(sys.argv[1:]))\n"
            "raise SystemExit(42)\n"
        )
        self.helper.chmod(0o755)
        self.environment = dict(os.environ, HOME=str(self.home), LEASE_CALL_LOG=str(self.log))
        self.environment.pop("SIMULATOR_LEASE_TOKEN", None)

    def run_runner(self):
        return subprocess.run(["bash", str(RUNNER), "target-device", "--skip-build"],
                              env=self.environment, capture_output=True, text=True, timeout=5)

    def test_runner_reserves_before_any_simulator_work_and_preserves_arguments(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 42, result.stderr)
        arguments = json.loads(self.log.read_text())
        self.assertEqual(arguments[0], "run")
        self.assertEqual(arguments[arguments.index("--device") + 1], "target-device")
        self.assertEqual(arguments[arguments.index("--") + 1:],
                         ["/bin/bash", str(RUNNER), "target-device", "--skip-build"])

    def test_existing_reservation_is_checked_before_simulator_work(self):
        self.environment["SIMULATOR_LEASE_TOKEN"] = "interactive-token"
        result = self.run_runner()
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(json.loads(self.log.read_text()),
                         ["check", "--token", "interactive-token", "--device", "target-device"])


if __name__ == "__main__":
    unittest.main()
