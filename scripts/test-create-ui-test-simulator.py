import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("simulator_selection", pathlib.Path(__file__).with_name("create-ui-test-simulator.py"))
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


def device(name, available=True):
    return {"name": name, "deviceTypeIdentifier": "type." + name, "isAvailable": available}


class SimulatorSelectionTests(unittest.TestCase):
    def test_newer_runtime_does_not_replace_the_selected_sdk_runtime(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro Max"), device("iPad Pro 13-inch")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo"), device("iPad New")],
        }
        for family in ["iPhone", "iPad"]:
            runtime, selected = selection.select_template(devices, family, "27.0")
            self.assertEqual(runtime, "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
            self.assertIn(selected, devices[runtime])

    def test_unavailable_and_other_platforms_do_not_supply_a_template(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro Max", False), device("iPhone 18 Pro")],
            "com.apple.CoreSimulator.SimRuntime.tvOS-27-0": [device("iPhone misleading")],
        }
        self.assertEqual(selection.select_template(devices, "iPhone", "27.0")[1]["name"], "iPhone 18 Pro")

    def test_patch_versions_are_compared_numerically_within_the_sdk_release(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0-9": [device("iPhone 18 Pro Max")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0-10": [device("iPhone 18 Pro Max")],
        }
        self.assertEqual(selection.select_template(devices, "iPhone", "27.0")[0], "com.apple.CoreSimulator.SimRuntime.iOS-27-0-10")

    def test_missing_compatible_family_is_an_error(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPad Pro 13-inch")], "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo")]}
        with self.assertRaisesRegex(ValueError, "iPhone.*27.0"):
            selection.select_template(devices, "iPhone", "27.0")

    def test_cli_creates_only_the_matching_runtime_and_records_the_owned_id(self):
        devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro Max")], "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo")]}}
        calls = []
        def invoke(command, **kwargs):
            calls.append(command)
            if "--show-sdk-version" in command:
                return "27.0\n"
            if "list" in command:
                return json.dumps(devices)
            return "owned-id\n"
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "output"
            with patch("sys.argv", ["create-ui-test-simulator.py", "--family", "iPhone"]), patch.dict(os.environ, GITHUB_OUTPUT=str(output)), patch.object(selection.subprocess, "check_output", invoke), patch("sys.stdout", new_callable=io.StringIO):
                selection.main()
            self.assertEqual(calls[-1], ["xcrun", "simctl", "create", "tsk isolated iPhone", "type.iPhone 18 Pro Max", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
            self.assertEqual(output.read_text(), "id=owned-id\n")


if __name__ == "__main__":
    unittest.main()
