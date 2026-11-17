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
PHONE = "-only-testing:TskUITests/TskUITests/testCaptureReviewCancelSaveAndRelaunch"


class SelectionTests(unittest.TestCase):
    def test_smoke_is_the_two_reviewed_product_journeys(self):
        filters = selection.selection("smoke", "iPhone")
        self.assertEqual(selection.selected_methods(filters), {
            "TskUITests/TskUITests/testCaptureReviewCancelSaveAndRelaunch",
            "TskUITests/TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion",
        })
        self.assertTrue(all(item.count("/") == 2 for item in filters))
        self.assertFalse(selection.requires_sync_server(filters))
        self.assertFalse(selection.requires_sync_peer(filters))

    def test_nightly_and_on_demand_classify_every_method_once(self):
        nightly = selection.selected_methods(selection.selection("full", "iPhone"))
        diagnostic = selection.selected_methods(selection.selection("diagnostic", "iPhone"))
        self.assertEqual(len(nightly), 34)
        self.assertEqual(len(diagnostic), 27)
        self.assertFalse(nightly & diagnostic)
        self.assertEqual({method for method in nightly if "/TaskNavigationUITests/" in method}, {
            "TskUITests/TaskNavigationUITests/testInstalledOpenTaskURLUsesFreshRecordExpandsContainingListAndReturnsWithColdMissingIdentity",
            "TskUITests/TaskNavigationUITests/testInstalledOpenViewURLsReachHiddenViewsExactProjectAndRenamedSavedViewWithoutChangingFavorites",
            "TskUITests/TaskNavigationUITests/testNavigationCallbacksReportActualDraftFailureAndSuccessfulDestination",
        })
        self.assertEqual(nightly | diagnostic, selection.test_methods())
        self.assertLess(selection.selected_methods(selection.selection("smoke", "iPhone")), nightly)
        self.assertIn("TskUITests/TaskBulkSelectionUITests/testBulkDateFailureRetainsPendingOperationAndEverySelectedTask", nightly)
        self.assertIn("TskUITests/TaskBulkSelectionUITests/testSelectionResolvesValidEditorAndRetainsInvalidDraft", nightly)
        self.assertIn("TskUITests/TaskActionURLUITests/testModifySystemURLSavesAllFieldsTagModesClearsAndAtomicRejections", nightly)
        self.assertIn("TskUITests/TaskActionURLUITests/testModifyURLSettlesActiveEditingRevealsTimedResultAndPreservesInvalidDraft", nightly)
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
        self.assertEqual((len(workspace), len(rows)), (25, 9))
        for partition, filters in groups.items():
            self.assertEqual(selection.requires_sync_server(filters), partition == "workspace")
            self.assertEqual(selection.requires_sync_peer(filters), partition == "workspace")
        for cls in ("SpotlightUITests",
                    "TaskNotificationUITests", "MissedNotificationUITests", "ReminderImportUITests"):
            self.assertTrue(any("/" + cls + "/" in case for case in workspace), cls)
        self.assertFalse(any("/TaskRowEditingUITests/" in case for case in workspace))
        result = subprocess.run(["python3", str(ROOT / "scripts/ui-test-selection.py"), "select", "full", "iPhone", "--partition", "row-editing"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(selection.selected_methods(result.stdout.splitlines()), rows)

    def test_focused_suites_keep_touch_annotation_and_original_menu_contracts(self):
        menu = selection.selected_methods(selection.selection("menu", "iPhone"))
        self.assertEqual(menu, {
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuDismissesTitleAndNoteKeyboard",
            "TskUITests/TaskRowEditingUITests/testNativeProjectMenuRetainsScrolledPositionWhileOpen",
            "TskUITests/TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
        })
        text = selection.selection("text", "iPhone")
        self.assertEqual(len(selection.selected_methods(text)), 1)
        self.assertFalse(selection.requires_sync_server(text))
        for suite in ("text", "menu", "diagnostic"):
            self.assertFalse(selection.requires_sync_server(selection.selection(suite, "iPhone")))
        regression = selection.selection("regression", "iPhone")
        self.assertEqual(len(selection.selected_methods(regression)), 4)
        self.assertFalse(selection.requires_sync_server(regression))
        self.assertFalse(selection.requires_sync_peer(regression))

    def test_renamed_and_unknown_selectors_fail_instead_of_disappearing(self):
        with patch.object(selection, "test_methods", return_value=set()):
            with self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.selection("smoke", "iPhone")
        for filters in (["-only-testing:TskUITests/MissingTests"], [PHONE, "-only-testing:TskUITests/MissingTests"],
                        [PHONE, "-skip-testing:TskUITests/MissingTests"]):
            with self.subTest(filters=filters), self.assertRaisesRegex(ValueError, "Unknown UI test selector"):
                selection.requires_action_fixture(filters)


    def test_filters_control_sync_and_action_fixture_requirements(self):
        self.assertFalse(selection.requires_action_fixture([PHONE]))
        with self.assertRaisesRegex(ValueError, "contains no UI tests"):
            selection.requires_action_fixture([PHONE, PHONE.replace("-only-testing:", "-skip-testing:")])
        for cls in ("TaskActionURLUITests", "TaskNavigationUITests"):
            self.assertTrue(selection.requires_action_fixture(["-only-testing:TskUITests/" + cls]))
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
    def run_runner(self, filters=(), main_status=0, prebuilt=False, owned_ci=False):
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
if name == 'xcodebuild' and 'test-without-building' in args:
    sys.exit(int(os.environ['UI_TEST_MAIN_STATUS']))
""")
            tool.chmod(0o755)
            for name in ("xcrun", "xcodebuild", "osascript", "codesign"):
                (root / name).symlink_to(tool)
            environment = {key: value for key, value in os.environ.items() if not key.startswith(("TSK_", "TEST_RUNNER_"))}
            environment.update(HOME=str(test_home), PATH=str(root) + os.pathsep + os.environ["PATH"], UI_TEST_COMMAND_LOG=str(log), UI_TEST_MAIN_STATUS=str(main_status), CI="false")
            if owned_ci:
                environment.update(CI="true", TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR="1", TSK_EVENTKIT_EVIDENCE_DIR=str(root / "evidence"))
            result = subprocess.run([
                "/bin/bash", str(ROOT / "scripts/run-ui-tests.sh"), "owned-test-device",
                "-project", "Tsk.xcodeproj", "-scheme", "Tsk", *filters,
                "-derivedDataPath", str(root / "DerivedData"), "-resultBundlePath", str(root / "Results.xcresult"),
            ], env=environment, capture_output=True, text=True, timeout=30)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def test_smoke_builds_once_without_action_fixture_install(self):
        result, calls = self.run_runner([PHONE])
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in calls if call["name"] == "xcodebuild"]
        self.assertEqual(len(builds), 2)
        self.assertIn("build-for-testing", builds[0])
        self.assertIn("test-without-building", builds[1])
        self.assertFalse(any("TskActionFixture.app" in argument for call in calls for argument in call["args"]))
        self.assertTrue(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))

    def test_full_executes_once_and_preserves_failure_and_cleanup(self):
        result, calls = self.run_runner(main_status=65)
        self.assertEqual(result.returncode, 65, result.stderr)
        executions = [call["args"] for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 1)
        self.assertTrue(any("TskActionFixture.app" in argument for call in calls for argument in call["args"]))
        self.assertTrue(any(call["args"] == ["simctl", "shutdown", "owned-test-device"] for call in calls))

    def test_url_navigation_installs_its_action_callback_host(self):
        result, calls = self.run_runner(["-only-testing:TskUITests/TaskNavigationUITests"])
        self.assertEqual(result.returncode, 0, result.stderr)
        installs = [call["args"] for call in calls if call["name"] == "xcrun" and call["args"][:2] == ["simctl", "install"]]
        self.assertTrue(any(call[-1].endswith("TskActionFixture.app") for call in installs))

    def test_smoke_main_failure_is_preserved(self):
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


    def test_owned_smoke_executes_through_the_boundary_wrapper(self):
        result, calls = self.run_runner([PHONE], owned_ci=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        executions = [call for call in calls if call["name"] == "xcodebuild" and "test-without-building" in call["args"]]
        self.assertEqual(len(executions), 1)


if __name__ == "__main__":
    unittest.main()
