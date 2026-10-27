#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("simulator", Path(__file__).with_name("create-ui-test-simulator.py"))
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)


def device(name, available=True):
    return {"name": name, "deviceTypeIdentifier": name, "isAvailable": available}


class SimulatorSelectionTests(unittest.TestCase):
    def test_explicit_runtime_remains_fixed_when_selected_toolchain_sdk_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport json,os,pathlib,sys\na=sys.argv[1:]\nif a==['--sdk','iphonesimulator','--show-sdk-version']: print('27.1')\nelif a==['simctl','list','devices','available','--json']: print(json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-27-0':[{'name':'iPhone 18 Pro Max','deviceTypeIdentifier':'phone-type','isAvailable':True}]}}))\nelif a[:2]==['simctl','create']:\n pathlib.Path(os.environ['CREATE_RECEIPT']).write_text(json.dumps(a))\n print('owned-probe-device')\nelse: sys.exit(99)\n")
            tool.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""), GITHUB_OUTPUT=str(root / "output"), CREATE_RECEIPT=str(root / "created.json"))
            result = subprocess.run([sys.executable, str(Path(simulator.__file__)), "--family", "iPhone", "--runtime-version", "27.0"], env=environment, capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((root / "created.json").read_text())[-1], "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
            self.assertIn("SDK 27.1", result.stdout)
            self.assertEqual((root / "output").read_text(), "id=owned-probe-device\n")

    def test_newer_installed_runtime_does_not_override_selected_sdk(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro Max")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo")],
        }
        runtime, selected = simulator.select_template(devices, "iPhone", "27.0")
        self.assertEqual(runtime, "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        self.assertEqual(selected["name"], "iPhone 18 Pro Max")

    def test_matching_runtime_keeps_family_and_large_pro_preference(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
            device("iPhone 18 Pro Max"), device("iPad Pro 11-inch (M5)"),
            device("iPad Pro 13-inch (M5)"), device("iPad Air 13-inch (M4)"),
        ]}
        _, selected = simulator.select_template(devices, "iPad", "27.0.0")
        self.assertEqual(selected["name"], "iPad Pro 13-inch (M5)")

    def test_unavailable_devices_are_not_templates(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
            device("iPhone 18 Pro Max", available=False), device("iPhone 18 Pro"),
        ]}
        _, selected = simulator.select_template(devices, "iPhone", "27.0")
        self.assertEqual(selected["name"], "iPhone 18 Pro")

    def test_missing_matching_runtime_fails_without_using_a_future_runtime(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo")]}
        with self.assertRaisesRegex(ValueError, "SDK 27.0"):
            simulator.select_template(devices, "iPhone", "27.0")


if __name__ == "__main__":
    unittest.main()
