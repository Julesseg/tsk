import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("ui_selection", ROOT / "scripts/ui-test-selection.py")
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)
SHARE = "-only-testing:TskUITests/ShareCaptureUITests"
PHONE = "-only-testing:TskUITests/TskUITests/testCaptureReviewCancelSaveAndRelaunch"
SPOTLIGHT = "-only-testing:TskUITests/SpotlightUITests"


class SelectionTests(unittest.TestCase):
    def test_smoke_is_a_bounded_subset_of_full_coverage(self):
        for family, count in (("iPhone", 22), ("iPad", 19)):
            with self.subTest(family=family):
                smoke = selection.selected_methods(selection.selection("smoke", family))
                full = selection.selected_methods(selection.selection("full", family))
                self.assertEqual(len(smoke), count)
                self.assertLess(smoke, full)
        pad = selection.selected_methods(selection.selection("smoke", "iPad"))
        self.assertEqual(sum("/iPadWorkspaceUITests/" in test for test in pad), 3)
        self.assertTrue(any(test.endswith("/testIndependentNativeTextViewRecognizesPlainAndCommandKeys") for test in pad))

    def test_full_keeps_the_existing_device_coverage(self):
        self.assertEqual(selection.selection("full", "iPhone"), [])
        pad = selection.selected_methods(selection.selection("full", "iPad"))
        self.assertEqual(sum("/CalendarPresentationUITests/" in test for test in pad), 5)
        self.assertEqual(sum("/TaskPresentationUITests/" in test for test in pad), 4)
        self.assertEqual(len(pad), 63)
        for suite, family in (("diagnostic", "iPhone"), ("full", "iPad"), ("smoke", "iPhone"), ("smoke", "iPad")):
            self.assertTrue(selection.selected_methods(selection.selection(suite, family)))
        self.assertEqual(len(selection.selected_methods(selection.selection("diagnostic", "iPhone"))), 13)

    def test_keyboard_diagnostics_keep_existing_state_and_transport_checks_on_both_devices(self):
        for family in ("iPhone", "iPad"):
            selected = selection.selected_methods(selection.selection("keyboard", family))
            self.assertEqual(len(selected), 11 if family == "iPhone" else 9)
            self.assertIn("TskUITests/CalendarTodayUITests/testInjectedCalendarReadFailureKeepsTaskCaptureAndCompletionUsable", selected)
            self.assertIn("TskUITests/ShareCaptureUITests/testInstalledExtensionFirstFailureCancelEditableSaveAndDurableAppReadback", selected)
            self.assertIn("TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer", selected)
            self.assertIn("TskUITests/TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations", selected)
            self.assertIn("TskUITests/TypedFilterUITests/testTypedSavedViewMembershipAfterEditingAndPersistentReopen", selected)
            self.assertEqual("TskUITests/TskDependencyUITests/testDependencySelectionCycleFailureCompletionAndRemovalPersistInToday" in selected, family == "iPhone")
            self.assertEqual("TskUITests/TskUITests/testOrganizationProjectViewsAndListActionsPersist" in selected, family == "iPhone")

    def test_renamed_tests_fail_instead_of_silently_disappearing(self):
        with patch.object(selection, "test_methods", return_value=set()):
            with self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.selection("smoke", "iPhone")
        for filters in (["-only-testing:TskUITests/MissingTests"], [PHONE, "-only-testing:TskUITests/MissingTests"], [PHONE, "-skip-testing:TskUITests/MissingTests"]):
            with self.subTest(filters=filters), self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.phases(filters)

    def test_text_diagnostics_cover_editing_share_and_native_transport_without_sync(self):
        for family in ("iPhone", "iPad"):
            filters = selection.selection("text", family)
            selected = selection.selected_methods(filters)
            self.assertEqual(selected, {
                "TskUITests/ShareCaptureUITests/testInstalledExtensionFirstFailureCancelEditableSaveAndDurableAppReadback",
                "TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys",
                "TskUITests/TaskAttributeUITests/testAllFiveLocalDefinitionTypesPersistAfterNativeCreation",
                "TskUITests/SeriesTransitionUITests/testExplicitSuccessorPreviewCancelCommitAndRetiredHistoryRemainSeparate",
                "TskUITests/TypedFilterUITests/testTypedSavedViewMembershipAfterEditingAndPersistentReopen",
            })
            self.assertLess(selected, selection.selected_methods(selection.selection("full", family)))
            self.assertEqual(selection.phases(filters), ["share", "main"])
            self.assertFalse(selection.requires_sync_peer(filters))

    def test_every_canonical_selection_retains_the_required_keyboard_transport_cases(self):
        spec = importlib.util.spec_from_file_location("hid_owner", ROOT / "scripts/with-native-keyboard-hid.py")
        owner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owner)
        for suite, family in (("smoke", "iPhone"), ("smoke", "iPad"), ("full", "iPhone"), ("full", "iPad"), ("diagnostic", "iPhone"), ("keyboard", "iPhone"), ("keyboard", "iPad"), ("text", "iPhone"), ("text", "iPad")):
            with self.subTest(suite=suite, family=family):
                command = [
                    "xcodebuild", "test-without-building", "-destination", "platform=iOS Simulator,id=owned",
                    "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                    "-resultBundlePath", "Results.xcresult", *selection.selection(suite, family),
                    "-skip-testing:TskUITests/ShareCaptureUITests",
                    "-skip-testing:TskUITests/SpotlightUITests",
                ]
                owner.validate_command(command, "owned")

    def test_filters_control_share_and_main_phases(self):
        self.assertEqual(selection.phases([]), ["spotlight", "share", "main"])
        self.assertEqual(selection.phases([SPOTLIGHT]), ["spotlight"])
        self.assertEqual(selection.phases([SHARE]), ["share"])
        self.assertEqual(selection.phases([PHONE]), ["main"])
        self.assertEqual(selection.phases(["-only-testing:TskUITests", "-skip-testing:TskUITests/ShareCaptureUITests"]), ["spotlight", "main"])
        with self.assertRaises(ValueError):
            selection.phases([SHARE, "-skip-testing:TskUITests/ShareCaptureUITests"])

    def test_independent_peer_requires_the_matching_real_sync_ui_scenario(self):
        for suite, family, expected in (("smoke", "iPhone", True), ("smoke", "iPad", False), ("full", "iPhone", True), ("full", "iPad", True), ("diagnostic", "iPhone", True)):
            with self.subTest(suite=suite, family=family):
                self.assertEqual(selection.requires_sync_peer(selection.selection(suite, family)), expected)
        filters = selection.selection("smoke", "iPhone") + ["-skip-testing:TskUITests/SynchronizationUITests"]
        self.assertFalse(selection.requires_sync_peer(filters))


class RunnerTests(unittest.TestCase):
    def run_runner(self, filters=(), share_status=0, main_status=0, prebuilt=False, spotlight_status=0, boot_status=0, already_booted=False, interrupt_spotlight=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            if prebuilt:
                (root / "DerivedData/Build/Products/Debug-iphonesimulator/Tsk.app").mkdir(parents=True)
            log = root / "calls.jsonl"
            tool = root / "tool"
            tool.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['UI_TEST_COMMAND_LOG'], 'a') as output:
    output.write(json.dumps({'name': name, 'args': args}) + '\\n')
if name == 'xcrun' and args[:4] == ['simctl', 'list', 'devices', 'booted']:
    print(json.dumps({'devices': {'runtime': [{'udid': 'owned-test-device', 'state': 'Booted'}]} if os.environ['UI_TEST_ALREADY_BOOTED'] == '1' else {}}))
if name == 'xcrun' and args[:3] == ['simctl', 'list', 'devices'] and args[3] != 'booted':
    print(json.dumps({'devices': {'runtime': [{'udid': 'owned-test-device', 'deviceTypeIdentifier': 'phone-type', 'isAvailable': True}]}}))
if name == 'xcrun' and args[:2] == ['simctl', 'create']:
    import uuid
    print('spotlight-' + str(uuid.uuid4()))
if name == 'xcrun' and args[:2] == ['simctl', 'bootstatus'] and args[2].startswith('spotlight-'):
    sys.exit(int(os.environ['UI_TEST_BOOT_STATUS']))
if name == 'xcodebuild' and 'test-without-building' in args and any(arg.startswith('-only-testing:TskUITests/SpotlightUITests/') for arg in args):
    if os.environ['UI_TEST_INTERRUPT_SPOTLIGHT'] == '1':
        import signal
        os.kill(os.getppid(), signal.SIGTERM)
        import time
        time.sleep(5)
    sys.exit(int(os.environ['UI_TEST_SPOTLIGHT_STATUS']))
if name == 'xcodebuild' and 'test-without-building' in args and '-only-testing:TskUITests/ShareCaptureUITests' in args:
    sys.exit(int(os.environ['UI_TEST_SHARE_STATUS']))
if name == 'xcodebuild' and 'test-without-building' in args:
    sys.exit(int(os.environ['UI_TEST_MAIN_STATUS']))
""")
            tool.chmod(0o755)
            for name in ("xcrun", "xcodebuild", "osascript"):
                (root / name).symlink_to(tool)
            environment = {key: value for key, value in os.environ.items() if not key.startswith(("TSK_", "TEST_RUNNER_"))}
            environment.update(PATH=str(root) + os.pathsep + os.environ["PATH"], UI_TEST_COMMAND_LOG=str(log), UI_TEST_SHARE_STATUS=str(share_status), UI_TEST_MAIN_STATUS=str(main_status), UI_TEST_SPOTLIGHT_STATUS=str(spotlight_status), UI_TEST_BOOT_STATUS=str(boot_status), UI_TEST_ALREADY_BOOTED=str(int(already_booted)), UI_TEST_INTERRUPT_SPOTLIGHT=str(int(interrupt_spotlight)), CI="false")
            result = subprocess.run([
                "/bin/bash", str(ROOT / "scripts/run-ui-tests.sh"), "owned-test-device",
                "-project", "Tsk.xcodeproj", "-scheme", "Tsk", *filters,
                "-derivedDataPath", str(root / "DerivedData"), "-resultBundlePath", str(root / "Results.xcresult"),
            ], env=environment, capture_output=True, text=True, timeout=30)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def test_pad_smoke_builds_once_without_share_launch_or_fixture_install(self):
        result, calls = self.run_runner(selection.selection("smoke", "iPad"))
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in calls if call["name"] == "xcodebuild"]
        self.assertEqual(len(builds), 2)
        self.assertIn("build-for-testing", builds[0])
        self.assertIn("test-without-building", builds[1])
        self.assertNotIn(SHARE, builds[1])
        self.assertFalse(any("TskShareFixture.app" in argument for call in calls for argument in call["args"]))
        self.assertTrue(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))

    def test_share_only_runs_once_and_has_no_empty_main_phase(self):
        result, calls = self.run_runner([SHARE])
        self.assertEqual(result.returncode, 0, result.stderr)
        executions = [call["args"] for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 1)
        self.assertIn(SHARE, executions[0])

    def test_full_preserves_both_phases_and_share_failure(self):
        result, calls = self.run_runner(share_status=65)
        self.assertEqual(result.returncode, 65, result.stderr)
        executions = [call["args"] for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 5)
        self.assertIn(SHARE, executions[3])
        self.assertIn("-skip-testing:TskUITests/ShareCaptureUITests", executions[4])
        self.assertIn("-skip-testing:TskUITests/SpotlightUITests", executions[4])
        executed = [method for arguments in executions for method in selection.selected_methods(arguments)]
        self.assertEqual(set(executed), selection.selected_methods([]))
        self.assertEqual(len(executed), len(set(executed)))
        self.assertTrue(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))

    def test_smoke_main_failure_is_not_hidden_by_omitted_share_phase(self):
        result, calls = self.run_runner([PHONE], main_status=65)
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertTrue(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))

    def test_prebuilt_smoke_executes_without_repeating_the_build(self):
        result, calls = self.run_runner(["--skip-build", PHONE], prebuilt=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in calls if call["name"] == "xcodebuild"]
        self.assertEqual(len(builds), 1)
        self.assertIn("test-without-building", builds[0])
        self.assertNotIn("--skip-build", builds[0])

    def test_prebuilt_mode_rejects_missing_products(self):
        result, calls = self.run_runner(["--skip-build", PHONE])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call["name"] == "xcodebuild" for call in calls))

    def test_spotlight_cases_use_distinct_fresh_devices_and_keep_all_assertions_selected(self):
        result, calls = self.run_runner([SPOTLIGHT, "-skip-testing:TskUITests/SpotlightUITests/testReceivedEncryptedPeerCompletionReconcilesActualIndex"])
        self.assertEqual(result.returncode, 0, result.stderr)
        created = [call for call in calls if call["args"][:2] == ["simctl", "create"]]
        self.assertEqual(len(created), 2)
        self.assertTrue(all(call["args"][-2:] == ["phone-type", "runtime"] for call in created))
        executions = [call["args"] for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 2)
        selectors = {arg for args in executions for arg in args if arg.startswith("-only-testing:")}
        self.assertEqual(selectors, {"-only-testing:" + method for method in selection.selected_methods([SPOTLIGHT, "-skip-testing:TskUITests/SpotlightUITests/testReceivedEncryptedPeerCompletionReconcilesActualIndex"])})
        destinations = [args[args.index("-destination") + 1] for args in executions]
        self.assertEqual(len(set(destinations)), 2)
        deleted = [call["args"][2] for call in calls if call["args"][:2] == ["simctl", "delete"]]
        self.assertEqual(set(destinations), {"platform=iOS Simulator,id=" + device for device in deleted})
        self.assertFalse(any(call["args"] == ["simctl", "boot", "owned-test-device"] for call in calls))

    def test_spotlight_failure_survives_successful_main_and_cleans_owned_device(self):
        result, calls = self.run_runner(selection.selection("smoke", "iPhone"), spotlight_status=65)
        self.assertEqual(result.returncode, 65, result.stderr)
        executions = [call["args"] for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 3)
        self.assertIn("-skip-testing:TskUITests/SpotlightUITests", executions[-1])
        self.assertEqual(sum(call["args"][:2] == ["simctl", "delete"] for call in calls), 1)

    def test_failed_spotlight_boot_still_deletes_its_device_and_preserves_prebooted_device(self):
        result, calls = self.run_runner([SPOTLIGHT], boot_status=70, already_booted=True)
        self.assertEqual(result.returncode, 70, result.stderr)
        self.assertEqual(sum(call["args"][:2] == ["simctl", "delete"] for call in calls), 3)
        self.assertFalse(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))
        self.assertFalse(any(call["name"] == "xcodebuild" and "test-without-building" in call["args"] for call in calls))

    def test_interrupted_spotlight_execution_cleans_its_device_without_continuing(self):
        result, calls = self.run_runner([SPOTLIGHT], interrupt_spotlight=True)
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertEqual(sum(call["args"][:2] == ["simctl", "create"] for call in calls), 1)
        self.assertEqual(sum(call["args"][:2] == ["simctl", "delete"] for call in calls), 1)


class SpotlightCleanupTests(unittest.TestCase):
    def test_fallback_cleanup_only_removes_recorded_owned_devices_even_after_shutdown_timeout(self):
        spec = importlib.util.spec_from_file_location("spotlight_runner", ROOT / "scripts/run-spotlight-ui-tests.py")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory() as directory:
            manifest = pathlib.Path(directory) / "phases.json"
            manifest.write_text(json.dumps({"template": "template", "cases": [{"device": "owned"}, {"device": "already-deleted"}, {"device": "template"}]}))
            state = {"devices": {"runtime": [{"udid": device, "state": "Booted"} for device in ("template", "owned", "unrelated")]}}
            with patch.object(runner.subprocess, "check_output", return_value=json.dumps(state)), patch.object(runner.subprocess, "run", side_effect=[subprocess.TimeoutExpired("shutdown", 30), subprocess.CompletedProcess([], 0)]) as commands:
                self.assertEqual(runner.cleanup_manifest(manifest), 0)
            self.assertEqual([call.args[0] for call in commands.call_args_list], [["xcrun", "simctl", "shutdown", "owned"], ["xcrun", "simctl", "delete", "owned"]])


if __name__ == "__main__":
    unittest.main()
