import argparse
import pathlib
import re


PHONE_SMOKE = (
    "TaskRowEditingUITests",
    "WorkspaceSettingsUITests",
    "TskUITests/testCaptureReviewCancelSaveAndRelaunch",
    "TskUITests/testDescriptionEditAndCompletionPersistAcrossRelaunch",
    "SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
    "TaskAnnotationUITests/testToolbarSaveValidatesEditsAndDurablyReopensTimestampedAnnotations",
    "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys",
    "ShareCaptureUITests",
    "WidgetUITests",
    "SpotlightUITests/testSystemSpotlightOpensExactTaskAndLocalCompletionRemovesIndexEntry",
)
PAD_SMOKE = (
    "TaskRowEditingUITests",
    "WorkspaceSettingsUITests",
    "iPadWorkspaceUITests",
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
    "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys",
)
PAD_FULL = (
    "WorkspaceSettingsUITests",
    "ShareCaptureUITests", "SynchronizationUITests", "iPadWorkspaceUITests",
    "TaskAnnotationUITests", "TaskAutomationUITests", "RecurringTemplateUITests",
    "SeriesMetadataUITests", "SeriesTransitionUITests", "TaskAttributeUITests",
    "TypedFilterUITests", "ReminderImportUITests", "ContinuousReminderImportUITests",
    "TaskRowEditingUITests", "TaskPresentationUITests", "TaskActivityUITests", "ReminderRecurrenceUITests", "CalendarTodayUITests", "CalendarPresentationUITests",
    "WidgetUITests", "SpotlightUITests", "TaskNotificationUITests", "MissedNotificationUITests",
)
DIAGNOSTIC = (
    "ShareCaptureUITests", "CustomViewsUITests", "TaskAnnotationUITests", "MissedNotificationUITests",
    "SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
    "ReminderImportUITests/testRealEventKitCopyAndRecurrenceFixturePreserveSourcesAndDurableTasks",
    "ReminderRecurrenceUITests/testActualCurrentWeeklyCopyCreatesDurableTemplateAndPreservesCompletedSourceHistory",
    "SpotlightUITests", "WidgetUITests",
)
KEYBOARD = (
    "CalendarTodayUITests/testInjectedCalendarReadFailureKeepsTaskCaptureAndCompletionUsable",
    "WorkspaceSettingsUITests/testCreationPlacementAndEverySettingsDestination",
    "WorkspaceSettingsUITests/testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch",
    "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys",
    "ShareCaptureUITests",
    "AutomaticSynchronizationUITests",
    "SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
    "TypedFilterUITests/testTypedSavedViewMembershipAfterEditingAndPersistentReopen",
)
PHONE_KEYBOARD = (
    "TskDependencyUITests/testDependencySelectionCycleFailureCompletionAndRemovalPersistInToday",
    "TskUITests/testOrganizationProjectViewsAndListActionsPersist",
)
TEXT = (
    "ShareCaptureUITests",
    "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys",
    "TaskAttributeUITests/testAllFiveLocalDefinitionTypesPersistAfterNativeCreation",
    "SeriesTransitionUITests/testExplicitSuccessorPreviewCancelCommitAndRetiredHistoryRemainSeparate",
    "TypedFilterUITests/testTypedSavedViewMembershipAfterEditingAndPersistentReopen",
)
TEST_ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "TskUITests"


def test_methods():
    return {
        f"TskUITests/{path.stem}/{method}"
        for path in TEST_ROOT.glob("*.swift")
        for method in re.findall(r"^\s*func (test\w+)\(", path.read_text(), re.MULTILINE)
    }


def matches(test, selector):
    return test == selector or test.startswith(selector + "/")


def selected_methods(filters):
    only = [item.removeprefix("-only-testing:") for item in filters if item.startswith("-only-testing:")]
    skip = [item.removeprefix("-skip-testing:") for item in filters if item.startswith("-skip-testing:")]
    available = test_methods()
    for selector in only + skip:
        if not any(matches(test, selector) for test in available):
            raise ValueError("Unknown UI test selector: " + selector)
    return {
        test for test in available
        if (not only or any(matches(test, selector) for selector in only))
        and not any(matches(test, selector) for selector in skip)
    }


def selection(suite, family, partition="all"):
    if suite == "text":
        tests = TEXT
    elif suite == "keyboard":
        tests = KEYBOARD + (PHONE_KEYBOARD if family == "iPhone" else ())
    elif suite == "diagnostic":
        if family != "iPhone":
            raise ValueError("Diagnostic coverage requires iPhone")
        tests = DIAGNOSTIC
    elif suite == "full":
        tests = PAD_FULL if family == "iPad" else ()
    else:
        tests = PAD_SMOKE if family == "iPad" else PHONE_SMOKE
    filters = ["-only-testing:TskUITests/" + test for test in tests]
    available = test_methods()
    for item in filters:
        selector = item.removeprefix("-only-testing:")
        if not any(matches(test, selector) for test in available):
            raise ValueError("Unknown UI test selector: " + selector)
    if partition == "all":
        return filters
    selected = selected_methods(filters)
    rows = {test for test in selected if matches(test, "TskUITests/TaskRowEditingUITests")}
    row_group = rows
    if partition == "row-editing":
        chosen = row_group
    elif partition == "workspace":
        chosen = selected - row_group
    else:
        raise ValueError("Unknown UI partition: " + partition)
    if not chosen or partition == "row-editing" and not rows:
        raise ValueError("UI partition contains no selected row coverage")
    return ["-only-testing:" + test for test in sorted(chosen)]


def phases(filters):
    selected = selected_methods(filters)
    if not selected:
        raise ValueError("Selection contains no UI tests")
    share = {test for test in selected if matches(test, "TskUITests/ShareCaptureUITests")}
    return [phase for phase, enabled in (("share", share), ("main", selected - share)) if enabled]


def requires_sync_peer(filters):
    return "TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer" in selected_methods(filters)


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("select")
    select.add_argument("suite", choices=("smoke", "full", "diagnostic", "keyboard", "text"))
    select.add_argument("family", choices=("iPhone", "iPad"))
    select.add_argument("--partition", choices=("all", "workspace", "row-editing"), default="all")
    phase = commands.add_parser("phases")
    phase.add_argument("filters", nargs=argparse.REMAINDER)
    peer = commands.add_parser("sync-peer")
    peer.add_argument("filters", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.command == "select":
            output = selection(args.suite, args.family, args.partition)
        elif args.command == "phases":
            output = phases(args.filters)
        else:
            output = ["yes" if requires_sync_peer(args.filters) else "no"]
    except ValueError as error:
        parser.error(str(error))
    print("\n".join(output))


if __name__ == "__main__":
    main()
