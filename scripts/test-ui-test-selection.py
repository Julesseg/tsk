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


class SelectionTests(unittest.TestCase):
    def test_smoke_is_a_bounded_subset_of_full_coverage(self):
        for family, count in (("iPhone", 8), ("iPad", 6)):
            with self.subTest(family=family):
                smoke = selection.selected_methods(selection.selection("smoke", family))
                full = selection.selected_methods(selection.selection("full", family))
                self.assertEqual(len(smoke), count)
                self.assertLess(smoke, full)
        pad = selection.selected_methods(selection.selection("smoke", "iPad"))
        self.assertEqual(sum("/iPadWorkspaceUITests/" in test for test in pad), 1)
        self.assertFalse(any(test.endswith("/testIndependentNativeTextViewRecognizesPlainAndCommandKeys") for test in pad))

    def test_partitions_run_every_selected_method_once_and_preserve_all_native_cases(self):
        spec = importlib.util.spec_from_file_location("partition_owner", ROOT / "scripts/with-native-keyboard-hid.py")
        owner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owner)
        for suite in ("full",):
            for family in ("iPhone", "iPad"):
                with self.subTest(suite=suite, family=family):
                    original = selection.selected_methods(selection.selection(suite, family))
                    groups = [selection.selection(suite, family, partition) for partition in ("workspace", "row-editing")]
                    methods = [selection.selected_methods(group) for group in groups]
                    self.assertEqual(methods[0] | methods[1], original)
                    self.assertFalse(methods[0] & methods[1])
                    self.assertEqual(sum("/TaskRowEditingUITests/" in method for method in methods[1]), 7)
                    self.assertFalse(any("/TaskRowEditingUITests/" in method for method in methods[0]))
                    self.assertEqual(owner.selected_cases(groups[0]), owner.selected_cases(selection.selection(suite, family)))
                    self.assertFalse(owner.selected_cases(groups[1]))
                    command = ["xcodebuild", "test-without-building", "-destination", "platform=iOS Simulator,id=owned", "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never", "-resultBundlePath", "Results.xcresult", *groups[0], "-skip-testing:TskUITests/ShareCaptureUITests"]
                    owner.validate_command(command, "owned")
                    self.assertEqual(selection.requires_sync_peer(groups[0]), selection.requires_sync_peer(selection.selection(suite, family)))
                    self.assertFalse(selection.requires_sync_peer(groups[1]))

    def test_partition_cli_preserves_the_original_full_selection(self):
        result = subprocess.run(["python3", str(ROOT / "scripts/ui-test-selection.py"), "select", "full", "iPad", "--partition", "row-editing"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(selection.selected_methods(result.stdout.splitlines())), 7)

    def test_smoke_covers_task_round_trip_without_hardware_or_installed_system_tours(self):
        for family in ("iPhone", "iPad"):
            smoke = selection.selected_methods(selection.selection("smoke", family))
            full = selection.selected_methods(selection.selection("full", family))
            self.assertIn("TskUITests/TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion", smoke)
            self.assertNotIn("TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys", smoke)
            self.assertIn("TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys", full)
            self.assertFalse(selection.requires_native_keyboard(selection.selection("smoke", family)))
            self.assertTrue(selection.requires_native_keyboard(selection.selection("full", family)))
            self.assertEqual(selection.phases(selection.selection("smoke", family)), ["main"])
            for suite in ("ShareCaptureUITests", "WidgetUITests", "SpotlightUITests"):
                self.assertFalse(any("/" + suite + "/" in case for case in smoke))
                self.assertTrue(any("/" + suite + "/" in case for case in full))

    def test_full_keeps_the_existing_device_coverage(self):
        self.assertEqual(selection.selection("full", "iPhone"), [])
        phone = selection.selected_methods(selection.selection("full", "iPhone"))
        self.assertEqual(len(phone), 75)
        pad = selection.selected_methods(selection.selection("full", "iPad"))
        self.assertEqual(sum("/CalendarPresentationUITests/" in test for test in pad), 5)
        self.assertEqual(sum("/TaskPresentationUITests/" in test for test in pad), 4)
        self.assertEqual(len(pad), 66)
        for methods in (phone, pad):
            self.assertIn("TskUITests/RecurringTemplateUITests/testDecimalOccurrencePositionOffersCompletionAndPreservesSeriesAfterRelaunch", methods)
        for suite, family in (("diagnostic", "iPhone"), ("full", "iPad"), ("smoke", "iPhone"), ("smoke", "iPad")):
            self.assertTrue(selection.selected_methods(selection.selection(suite, family)))
        self.assertEqual(len(selection.selected_methods(selection.selection("diagnostic", "iPhone"))), 12)

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

    def test_full_and_diagnostics_retain_required_keyboard_transport_cases(self):
        spec = importlib.util.spec_from_file_location("hid_owner", ROOT / "scripts/with-native-keyboard-hid.py")
        owner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owner)
        for suite, family in (("full", "iPhone"), ("full", "iPad"), ("diagnostic", "iPhone"), ("keyboard", "iPhone"), ("keyboard", "iPad"), ("text", "iPhone"), ("text", "iPad")):
            with self.subTest(suite=suite, family=family):
                command = [
                    "xcodebuild", "test-without-building", "-destination", "platform=iOS Simulator,id=owned",
                    "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                    "-resultBundlePath", "Results.xcresult", *selection.selection(suite, family),
                    "-skip-testing:TskUITests/ShareCaptureUITests",
                ]
                owner.validate_command(command, "owned")

    def test_transport_selection_matches_owner_for_every_declared_case_and_partition(self):
        spec = importlib.util.spec_from_file_location("transport_owner", ROOT / "scripts/with-native-keyboard-hid.py")
        owner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owner)
        for method in selection.test_methods():
            filters = ["-only-testing:" + method]
            self.assertEqual(selection.requires_native_keyboard(filters), bool(owner.selected_cases(filters)), method)
        for family in ("iPhone", "iPad"):
            for partition, required in (("workspace", True), ("row-editing", False)):
                self.assertEqual(selection.requires_native_keyboard(selection.selection("full", family, partition)), required)

    def test_transport_cli_reports_required_input_and_rejects_unknown_tests(self):
        script = str(ROOT / "scripts/ui-test-selection.py")
        for filters, expected in ((selection.selection("smoke", "iPad"), "no"), (selection.selection("full", "iPad", "workspace"), "yes")):
            result = subprocess.run(["python3", script, "native-keyboard", "--", *filters], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected)
        result = subprocess.run(["python3", script, "native-keyboard", "--", "-only-testing:TskUITests/MissingTests"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_filters_control_share_and_main_phases(self):
        self.assertEqual(selection.phases([]), ["share", "main"])
        self.assertEqual(selection.phases([SHARE]), ["share"])
        self.assertEqual(selection.phases([PHONE]), ["main"])
        self.assertEqual(selection.phases(["-only-testing:TskUITests", "-skip-testing:TskUITests/ShareCaptureUITests"]), ["main"])
        with self.assertRaises(ValueError):
            selection.phases([SHARE, "-skip-testing:TskUITests/ShareCaptureUITests"])

    def test_independent_peer_requires_the_matching_real_sync_ui_scenario(self):
        for suite, family, expected in (("smoke", "iPhone", True), ("smoke", "iPad", False), ("full", "iPhone", True), ("full", "iPad", True), ("diagnostic", "iPhone", True)):
            with self.subTest(suite=suite, family=family):
                self.assertEqual(selection.requires_sync_peer(selection.selection(suite, family)), expected)
        filters = selection.selection("smoke", "iPhone") + ["-skip-testing:TskUITests/SynchronizationUITests"]
        self.assertFalse(selection.requires_sync_peer(filters))


class RunnerTests(unittest.TestCase):
    def run_runner(self, filters=(), share_status=0, main_status=0, prebuilt=False, owned_ci=False):
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
    print(json.dumps({'devices': {}}))
if name == 'xcodebuild' and 'test-without-building' in args and '-only-testing:TskUITests/ShareCaptureUITests' in args:
    sys.exit(int(os.environ['UI_TEST_SHARE_STATUS']))
if name == 'xcodebuild' and 'test-without-building' in args:
    sys.exit(int(os.environ['UI_TEST_MAIN_STATUS']))
""")
            tool.chmod(0o755)
            for name in ("xcrun", "xcodebuild", "osascript", "codesign"):
                (root / name).symlink_to(tool)
            environment = {key: value for key, value in os.environ.items() if not key.startswith(("TSK_", "TEST_RUNNER_"))}
            environment.update(PATH=str(root) + os.pathsep + os.environ["PATH"], UI_TEST_COMMAND_LOG=str(log), UI_TEST_SHARE_STATUS=str(share_status), UI_TEST_MAIN_STATUS=str(main_status), CI="false")
            if owned_ci:
                environment.update(CI="true", TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR="1", TSK_EVENTKIT_EVIDENCE_DIR=str(root / "evidence"))
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
        self.assertEqual(len(executions), 2)
        self.assertIn(SHARE, executions[0])
        self.assertIn("-skip-testing:TskUITests/ShareCaptureUITests", executions[1])
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

    def test_owned_native_selection_rejects_missing_transport_before_launching_tests(self):
        filters = ["-only-testing:TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys"]
        result, calls = self.run_runner(filters, owned_ci=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Selected hardware-keyboard tests require the owned native transport", result.stderr)
        self.assertFalse(any(call["name"] == "xcodebuild" for call in calls))

    def test_owned_smoke_executes_without_native_transport(self):
        result, calls = self.run_runner(selection.selection("smoke", "iPad"), owned_ci=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        executions = [call for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 1)


if __name__ == "__main__":
    unittest.main()
