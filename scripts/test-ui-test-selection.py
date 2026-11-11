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
    def test_smoke_is_the_three_reviewed_product_journeys(self):
        filters = selection.selection("smoke", "iPhone")
        self.assertEqual(selection.selected_methods(filters), {
            "TskUITests/TskUITests/testCaptureReviewCancelSaveAndRelaunch",
            "TskUITests/TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion",
            "TskUITests/TaskBulkSelectionUITests/testContinuousSelectionFreezesRowsBeforeReleaseAndCompletesDurably",
        })
        self.assertTrue(all(item.count("/") == 2 for item in filters))
        self.assertEqual(selection.phases(filters), ["main"])
        self.assertFalse(selection.requires_native_keyboard(filters))
        self.assertFalse(selection.requires_sync_server(filters))
        self.assertFalse(selection.requires_sync_peer(filters))

    def test_nightly_and_on_demand_classify_every_method_once(self):
        nightly = selection.selected_methods(selection.selection("full", "iPhone"))
        diagnostic = selection.selected_methods(selection.selection("diagnostic", "iPhone"))
        self.assertEqual(len(nightly), 32)
        self.assertEqual(len(diagnostic), 27)
        self.assertFalse(nightly & diagnostic)
        self.assertEqual(nightly | diagnostic, selection.test_methods())
        self.assertLess(selection.selected_methods(selection.selection("smoke", "iPhone")), nightly)
        self.assertIn("TskUITests/TaskBulkSelectionUITests/testBulkDateFailureRetainsPendingOperationAndEverySelectedTask", nightly)
        self.assertIn("TskUITests/TaskBulkSelectionUITests/testSelectionResolvesValidEditorAndRetainsInvalidDraft", nightly)
        self.assertIn("TskUITests/TaskBulkSelectionUITests/testSelectionPickerValueChangesKeepQuickActionsStationary", diagnostic)
        for suite in selection.SUITES:
            filters = selection.selection(suite, "iPhone")
            self.assertTrue(all(item.count("/") == 2 for item in filters))
            self.assertTrue(selection.selected_methods(filters) <= nightly | diagnostic)
            with self.subTest(suite=suite), self.assertRaisesRegex(ValueError, "Only iPhone"):
                selection.selection(suite, "iPad")
        with self.assertRaisesRegex(ValueError, "Unknown UI suite"):
            selection.selection("missing", "iPhone")

    def test_new_and_multiply_registered_methods_require_a_cadence_decision(self):
        available = selection.test_methods()
        with patch.object(selection, "test_methods", return_value=available | {"TskUITests/NewTests/testNew"}):
            with self.assertRaisesRegex(ValueError, "explicit cadence.*NewTests/testNew"):
                selection.selection("full", "iPhone")
        for name, value in (("NIGHTLY", selection.NIGHTLY + (selection.NIGHTLY[0],)),
                            ("ON_DEMAND", selection.ON_DEMAND + (selection.NIGHTLY[0],))):
            with patch.object(selection, name, value):
                with self.assertRaisesRegex(ValueError, "exactly one cadence"):
                    selection.selection("full", "iPhone")
        with patch.object(selection, "PHONE_SMOKE", selection.PHONE_SMOKE + (selection.ON_DEMAND[0],)):
            with self.assertRaisesRegex(ValueError, "subset of nightly"):
                selection.selection("smoke", "iPhone")

    def test_discovery_includes_inline_actor_attributes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / "ActorTests.swift").write_text("""import XCTest
@MainActor final class ActorTests: XCTestCase {
    @MainActor func testInlineAttribute() {}
    @MainActor
    func testSeparateAttribute() {}
    func testPlain() {}
}
""")
            with patch.object(selection, "TEST_ROOT", path):
                self.assertEqual(selection.test_methods(), {
                    "TskUITests/ActorTests/testInlineAttribute",
                    "TskUITests/ActorTests/testSeparateAttribute",
                    "TskUITests/ActorTests/testPlain",
                })

    def test_shards_cover_nightly_once_and_keep_system_fixtures_in_workspace(self):
        nightly = selection.selected_methods(selection.selection("full", "iPhone"))
        groups = {name: selection.selection("full", "iPhone", name) for name in ("workspace", "row-editing")}
        workspace = selection.selected_methods(groups["workspace"])
        rows = selection.selected_methods(groups["row-editing"])
        self.assertEqual(workspace | rows, nightly)
        self.assertFalse(workspace & rows)
        self.assertEqual((len(workspace), len(rows)), (21, 11))
        for partition, filters in groups.items():
            self.assertEqual(selection.requires_native_keyboard(filters), partition == "workspace")
            self.assertEqual(selection.requires_sync_server(filters), partition == "workspace")
            self.assertEqual(selection.requires_sync_peer(filters), partition == "workspace")
        for cls in ("ShareCaptureUITests", "WidgetUITests", "SpotlightUITests", "CalendarTodayUITests",
                    "TaskNotificationUITests", "MissedNotificationUITests", "ReminderImportUITests"):
            self.assertTrue(any("/" + cls + "/" in case for case in workspace), cls)
        self.assertFalse(any("/TaskRowEditingUITests/" in case for case in workspace))
        result = subprocess.run(["python3", str(ROOT / "scripts/ui-test-selection.py"), "select", "full", "iPhone", "--partition", "row-editing"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(selection.selected_methods(result.stdout.splitlines()), rows)

    def test_focused_suites_keep_product_input_and_original_menu_contracts(self):
        keyboard = selection.selected_methods(selection.selection("keyboard", "iPhone"))
        self.assertEqual(keyboard, {
            "TskUITests/TaskKeyboardCompatibilityUITests/testWorkspaceAndEditorCommandsKeepOwnershipAcrossFocus",
            "TskUITests/TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
        })
        menu = selection.selected_methods(selection.selection("menu", "iPhone"))
        self.assertEqual(menu - keyboard, {
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuDismissesTitleAndNoteKeyboard",
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuRetainsScrolledPositionWhileOpen",
        })
        text = selection.selection("text", "iPhone")
        self.assertEqual(len(selection.selected_methods(text)), 3)
        self.assertEqual(selection.phases(text), ["share", "main"])
        self.assertFalse(selection.requires_sync_server(text))
        for suite in ("keyboard", "text", "menu", "diagnostic"):
            self.assertTrue(selection.requires_native_keyboard(selection.selection(suite, "iPhone")))
            self.assertFalse(selection.requires_sync_server(selection.selection(suite, "iPhone")))
        regression = selection.selection("regression", "iPhone")
        self.assertEqual(len(selection.selected_methods(regression)), 5)
        self.assertEqual(selection.phases(regression), ["share", "main"])
        self.assertFalse(selection.requires_sync_server(regression))
        self.assertFalse(selection.requires_sync_peer(regression))
        self.assertFalse(selection.requires_native_keyboard(regression))

    def test_renamed_and_unknown_selectors_fail_instead_of_disappearing(self):
        with patch.object(selection, "test_methods", return_value=set()):
            with self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.selection("smoke", "iPhone")
        for filters in (["-only-testing:TskUITests/MissingTests"], [PHONE, "-only-testing:TskUITests/MissingTests"],
                        [PHONE, "-skip-testing:TskUITests/MissingTests"]):
            with self.subTest(filters=filters), self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.phases(filters)

    def test_transport_selection_matches_owner_for_every_method_and_suite(self):
        spec = importlib.util.spec_from_file_location("transport_owner", ROOT / "scripts/with-native-keyboard-hid.py")
        owner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owner)
        for method in selection.test_methods():
            filters = ["-only-testing:" + method]
            self.assertEqual(selection.requires_native_keyboard(filters), bool(owner.selected_cases(filters)), method)
        for suite in selection.SUITES:
            filters = selection.selection(suite, "iPhone")
            if selection.requires_native_keyboard(filters):
                command = ["xcodebuild", "test-without-building", "-destination", "platform=iOS Simulator,id=owned",
                           "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never", "-resultBundlePath", "Results.xcresult",
                           *filters, "-skip-testing:TskUITests/ShareCaptureUITests"]
                owner.validate_command(command, "owned")
        script = str(ROOT / "scripts/ui-test-selection.py")
        for suite, expected in (("smoke", "no"), ("full", "yes")):
            result = subprocess.run(["python3", script, "native-keyboard", "--", *selection.selection(suite, "iPhone")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected)

    def test_filters_control_share_phases_and_real_sync_requirements(self):
        self.assertEqual(selection.phases([]), ["share", "main"])
        self.assertEqual(selection.phases([SHARE]), ["share"])
        self.assertEqual(selection.phases([PHONE]), ["main"])
        self.assertEqual(selection.phases(["-only-testing:TskUITests", "-skip-testing:TskUITests/ShareCaptureUITests"]), ["main"])
        with self.assertRaises(ValueError):
            selection.phases([SHARE, "-skip-testing:TskUITests/ShareCaptureUITests"])
        full = selection.selection("full", "iPhone")
        self.assertTrue(selection.requires_sync_peer(full))
        self.assertFalse(selection.requires_sync_peer(full + ["-skip-testing:TskUITests/SynchronizationUITests"]))
        for case in selection.NIGHTLY + selection.ON_DEMAND:
            filters = ["-only-testing:TskUITests/" + case]
            expected = case in {
                "SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
                "MissedNotificationUITests/testRealEncryptedFinalStateDeliversNewMissedOnceAndCancelsReceivedCompletion",
            }
            self.assertEqual(selection.requires_sync_server(filters), expected, case)


class RunnerTests(unittest.TestCase):
    def run_runner(self, filters=(), share_status=0, main_status=0, prebuilt=False, owned_ci=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            test_home = root / "home"
            test_home.mkdir()
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
            environment.update(HOME=str(test_home), PATH=str(root) + os.pathsep + os.environ["PATH"], UI_TEST_COMMAND_LOG=str(log), UI_TEST_SHARE_STATUS=str(share_status), UI_TEST_MAIN_STATUS=str(main_status), CI="false")
            if owned_ci:
                environment.update(CI="true", TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR="1", TSK_EVENTKIT_EVIDENCE_DIR=str(root / "evidence"))
            result = subprocess.run([
                "/bin/bash", str(ROOT / "scripts/run-ui-tests.sh"), "owned-test-device",
                "-project", "Tsk.xcodeproj", "-scheme", "Tsk", *filters,
                "-derivedDataPath", str(root / "DerivedData"), "-resultBundlePath", str(root / "Results.xcresult"),
            ], env=environment, capture_output=True, text=True, timeout=30)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def test_smoke_builds_once_without_share_launch_or_fixture_install(self):
        result, calls = self.run_runner([PHONE])
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
        filters = ["-only-testing:TskUITests/TaskKeyboardCompatibilityUITests/testWorkspaceAndEditorCommandsKeepOwnershipAcrossFocus"]
        result, calls = self.run_runner(filters, owned_ci=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Selected hardware-keyboard tests require the owned native transport", result.stderr)
        self.assertFalse(any(call["name"] == "xcodebuild" for call in calls))

    def test_owned_smoke_executes_without_native_transport(self):
        result, calls = self.run_runner([PHONE], owned_ci=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        executions = [call for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 1)


if __name__ == "__main__":
    unittest.main()
