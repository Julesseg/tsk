import argparse
import json

from native_ui_readback import CHECKPOINTS
import pathlib
import re


PHONE_SMOKE = (
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
)

NIGHTLY = (
    'SeriesMetadataUITests/testSeriesMetadataPreviewCancelSaveAndPersistentFutureOccurrences',
    'TaskActionURLUITests/testActualCallbackDeliveryPreservesArgumentsAndDurableUUIDResultAndReportsInvalidInput',
    'TaskActionURLUITests/testCompleteOccurrenceURLPersistsAndMissingDeletedTargetsReturnErrors',
    'TaskActionURLUITests/testCompleteURLReturnsRichSavedTaskRevealsItAndProtectsNestedDrafts',
    'TaskActionURLUITests/testModifySystemURLSavesAllFieldsTagModesClearsAndAtomicRejections',
    'TaskActionURLUITests/testModifyURLSettlesActiveEditingRevealsTimedResultAndPreservesInvalidDraft',
    'TaskActionURLUITests/testSystemDeleteCallbackReturnsDurableDeletedResultAndRejectsSubsequentOpen',
    'TaskActionURLUITests/testSystemDeletePreservesInvalidLinkedDraftThenConfirmsWithoutOpeningDeletedEditor',
    'TaskActionURLUITests/testSystemFindCallbackReturnsRichPagesEmptyListsAndExplicitOversizeFailure',
    'TaskActionURLUITests/testSystemFindURLShowsCombinedResultsAndEmptyStateWithoutChangingWorkspace',
    'TaskActionURLUITests/testURLSavesValidDraftAndRetainsInvalidDraftWithoutCreatingTask',
    'TaskBulkSelectionUITests/testBulkDateFailureRetainsPendingOperationAndEverySelectedTask',
    'TaskBulkSelectionUITests/testScheduledSlotSelectsOnTouchDownAndSweepsWithoutMovingRows',
    'TaskNavigationUITests/testInstalledOpenTaskURLUsesFreshRecordExpandsContainingListAndReturnsWithColdMissingIdentity',
    'TaskNavigationUITests/testInstalledOpenViewURLsReachPlannerInboxAndExactProjects',
    'TaskNavigationUITests/testNavigationCallbacksReportActualDraftFailureAndSuccessfulDestination',
    'TaskPresentationUITests/testOccurrenceCircleCompletionAndGenuineFailureKeepSeriesScope',
    'TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
    'TaskRowEditingUITests/testSupportingInformationEditsKeepTheExpandedDraftAndPersist',
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
)

ON_DEMAND = (
    'CalendarPresentationUITests/testCalendarVisibilityTogglesFilterIndependentlyAndPersistAcrossLaunches',
    'CalendarPresentationUITests/testDisplayedDayCalendarReadsEventsWithoutChangingTasks',
    'CalendarPresentationUITests/testPopulatedCalendarMixesTimedEventsAndTasksAcrossAppearances',
    'CalendarPresentationUITests/testReadFailureHidesCalendarAndSettingsRetryRecoversWithTasksUsable',
    'RecurringTemplateUITests/testRecordedRealGeneratorOccurrenceEditsAndCompletesWithoutChangingItsTemplate',
    'RecurringTemplateUITests/testRecurringTemplateValidationCreationInspectionAndPersistentReopen',
    'SynchronizationUITests/testConnectionValidationPersistenceAndServerFailureRetainOfflineTask',
    'TaskActivityUITests/testOrdinaryTaskInformationStartStopPersistentReopenAndCompletionClearActiveState',
    'TaskActionURLUITests/testOversizedResultAndFailedDeliveryKeepExactlyOneDurableTaskPerAdd',
    'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations',
    'TaskBulkSelectionUITests/testSelectionPickerValueChangesKeepQuickActionsStationary',
    'TaskPresentationUITests/testMatchedPopulatedTaskListsAcrossAppearanceAndAccessibilityText',
    'TaskRowEditingUITests/testAppearanceAndAccessibilityOverflow',
    'TaskRowEditingUITests/testLongTitleNearBottomKeepsKeyboardAndScrollingUsable',
    'TaskRowEditingUITests/testMiddleRowOpensSpaceAroundItsFixedHeader',
    'TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal',
    'TaskRowEditingUITests/testNativeProjectMenuDismissesTitleAndNoteKeyboard',
    'TaskRowEditingUITests/testNativeProjectMenuRetainsScrolledPositionWhileOpen',
    'TaskRowEditingUITests/testSupportingInformationOverflowAndEmptyActionsAtAccessibilitySize',
    'TaskRowEditingUITests/testDayPageAnchorAndMembershipChangeAfterCollapse',
    'TaskScheduledUITests/testCompletedPlannerRowsRetainPageOrderAndCheckedStateAfterRelaunch',
    'TaskScheduledUITests/testNativeDraggingSavesLastCrossedIntentAndManualOrder',
    'TaskScheduledUITests/testNonMidnightScheduledEditsKeepOtherDatesAndPersist',
    'WorkspaceSettingsUITests/testSettingsRemainReachableAtLargestTextSize',
    'WorkspaceSettingsUITests/testSynchronizationProgressStaysBesideWorkspaceTitle',
)

DIAGNOSTIC = ON_DEMAND
TEXT = (
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
)
MENU = (
    "TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
    "TaskRowEditingUITests/testNativeProjectMenuDismissesTitleAndNoteKeyboard",
    "TaskRowEditingUITests/testNativeProjectMenuRetainsScrolledPositionWhileOpen",
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
)
REGRESSION = (
    "TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
    "TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion",
    "TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening",
)
SUITES = dict(smoke=PHONE_SMOKE, full=NIGHTLY, diagnostic=DIAGNOSTIC,
              text=TEXT, menu=MENU, regression=REGRESSION)
TEST_ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "TskUITests"
TASK_PARTITION = {
    'RecurringTemplateUITests', 'SeriesMetadataUITests', 'SeriesTransitionUITests',
    'TaskActivityUITests', 'TaskBulkSelectionUITests', 'TaskRowEditingUITests',
    'TaskScheduledUITests', 'TskUITests',
}


def test_methods():
    return {
        f"TskUITests/{path.stem}/{method}"
        for path in TEST_ROOT.glob("*.swift")
        for method in re.findall(r"^\s*(?:@\w+(?:\([^\n]*?\))?[ \t]+)*func (test\w+)\(", path.read_text(), re.MULTILINE)
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


def validate_cadence():
    available = test_methods()
    registered = ["TskUITests/" + case for case in NIGHTLY + ON_DEMAND]
    if len(registered) != len(set(registered)):
        raise ValueError("Each UI test must have exactly one cadence")
    unknown = set(registered) - available
    if unknown:
        raise ValueError("Unknown UI test selector: " + ", ".join(sorted(unknown)))
    unregistered = available - set(registered)
    if unregistered:
        raise ValueError("UI tests need an explicit cadence: " + ", ".join(sorted(unregistered)))
    if not set(CHECKPOINTS) <= set(NIGHTLY + ON_DEMAND):
        raise ValueError("Native readback checkpoint names must match retained methods")
    if any(not phases or len(phases) != len(set(phases)) for phases in CHECKPOINTS.values()):
        raise ValueError("Native readback checkpoints must be nonempty and unique")
    if not set(PHONE_SMOKE) <= set(NIGHTLY):
        raise ValueError("Smoke must be a subset of nightly coverage")


def selection(suite, family, partition="all"):
    if family != "iPhone":
        raise ValueError("Only iPhone UI coverage is supported")
    validate_cadence()
    if suite not in SUITES:
        raise ValueError("Unknown UI suite: " + suite)
    tests = SUITES[suite]
    filters = ["-only-testing:TskUITests/" + test for test in tests]
    available = test_methods()
    for item in filters:
        selector = item.removeprefix("-only-testing:").removeprefix("-skip-testing:")
        if not any(matches(test, selector) for test in available):
            raise ValueError("Unknown UI test selector: " + selector)
    if partition == "all":
        return filters
    selected = selected_methods(filters)
    rows = {test for test in selected if matches(test, "TskUITests/TaskRowEditingUITests")}
    row_group = {test for test in selected if test.split('/')[1] in TASK_PARTITION}
    if partition == "row-editing":
        chosen = row_group
    elif partition == "workspace":
        chosen = selected - row_group
    else:
        raise ValueError("Unknown UI partition: " + partition)
    if not chosen or partition == "row-editing" and not rows:
        raise ValueError("UI partition contains no selected row coverage")
    return ["-only-testing:" + test for test in sorted(chosen)]


def requires_action_fixture(filters):
    selected = selected_methods(filters)
    if not selected:
        raise ValueError("Selection contains no UI tests")
    return any(test.split("/")[1] in {"TaskActionURLUITests", "TaskNavigationUITests"}
               for test in selected)


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("select")
    select.add_argument("suite", choices=SUITES)
    select.add_argument("family", choices=("iPhone",))
    select.add_argument("--partition", choices=("all", "workspace", "row-editing"), default="all")
    fixture = commands.add_parser("action-fixture")
    fixture.add_argument("filters", nargs=argparse.REMAINDER)
    readback = commands.add_parser("native-readback")
    readback.add_argument("filters", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.command == "select":
            output = selection(args.suite, args.family, args.partition)
        elif args.command == "native-readback":
            selected = selected_methods(args.filters)
            output = [json.dumps({key: value for key, value in CHECKPOINTS.items() if "TskUITests/" + key in selected})]
        elif args.command == "action-fixture":
            output = ["yes" if requires_action_fixture(args.filters) else "no"]
    except ValueError as error:
        parser.error(str(error))
    print("\n".join(output))


if __name__ == "__main__":
    main()
