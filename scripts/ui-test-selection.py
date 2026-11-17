import argparse
import pathlib
import re


PHONE_SMOKE = (
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
)

NIGHTLY = (
    'ContinuousReminderImportUITests/testActualSourceEditIntoRecurringRuleIsPreservedAndAutomaticMovePauses',
    'ContinuousReminderImportUITests/testInterruptionAndActualPermissionResetAfterCommitLeaveSourceAndTaskAvailable',
    'ContinuousReminderImportUITests/testRealContinuousMoveSourceChangesForegroundRescanAndDurableReopen',
    'CustomViewsUITests/testRawViewValidationSaveEditReopenResultsActionsAndDeletion',
    'ReminderImportUITests/testRealEventKitCopyAndRecurrenceFixturePreserveSourcesAndDurableTasks',
    'ReminderRecurrenceUITests/testActualCurrentWeeklyMoveRemovesOnlyVerifiedRemainderAfterDurableTemplateSave',
    'SeriesMetadataUITests/testSeriesMetadataPreviewCancelSaveAndPersistentFutureOccurrences',
    'SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer',
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
    'TaskBulkSelectionUITests/testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch',
    'TaskBulkSelectionUITests/testSelectionResolvesValidEditorAndRetainsInvalidDraft',
    'TaskNavigationUITests/testInstalledOpenTaskURLUsesFreshRecordExpandsContainingListAndReturnsWithColdMissingIdentity',
    'TaskNavigationUITests/testInstalledOpenViewURLsReachHiddenViewsExactProjectAndRenamedSavedViewWithoutChangingFavorites',
    'TaskNavigationUITests/testNavigationCallbacksReportActualDraftFailureAndSuccessfulDestination',
    'TaskPresentationUITests/testOccurrenceCircleCompletionAndGenuineFailureKeepSeriesScope',
    'TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
    'TaskRowEditingUITests/testSupportingInformationEditsKeepTheExpandedDraftAndPersist',
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
    'WorkspaceSettingsUITests/testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch',
)

ON_DEMAND = (
    'CalendarPresentationUITests/testCalendarVisibilityTogglesFilterIndependentlyAndPersistAcrossLaunches',
    'CalendarPresentationUITests/testOverviewHoursSaveAcrossLaunchAndKeepEventsOutsideTheRange',
    'CalendarPresentationUITests/testPopulatedCalendarOnlyShowsTimeAndTitleAboveTasksAcrossAppearances',
    'CalendarPresentationUITests/testReadFailureHidesCalendarAndSettingsRetryRecoversWithTasksUsable',
    'RecurringTemplateUITests/testRecordedRealGeneratorOccurrenceEditsAndCompletesWithoutChangingItsTemplate',
    'RecurringTemplateUITests/testRecurringTemplateValidationCreationInspectionAndPersistentReopen',
    'ReminderImportUITests/testDeniedRealRemindersPermissionKeepsOrdinaryTaskWorkspaceUsable',
    'ReminderRecurrenceUITests/testActualCurrentWeeklyCopyCreatesDurableTemplateAndPreservesCompletedSourceHistory',
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
    'TaskRowEditingUITests/testUpcomingAnchorAndMembershipChangeAfterCollapse',
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
    "WorkspaceSettingsUITests/testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch",
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


def requires_sync_peer(filters):
    return "TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer" in selected_methods(filters)


def requires_sync_server(filters):
    return bool(selected_methods(filters) & {
        "TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
    })


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("select")
    select.add_argument("suite", choices=("smoke", "full", "diagnostic", "text", "regression", "menu"))
    select.add_argument("family", choices=("iPhone",))
    select.add_argument("--partition", choices=("all", "workspace", "row-editing"), default="all")
    peer = commands.add_parser("sync-peer")
    peer.add_argument("filters", nargs=argparse.REMAINDER)
    server = commands.add_parser("sync-server")
    server.add_argument("filters", nargs=argparse.REMAINDER)
    fixture = commands.add_parser("action-fixture")
    fixture.add_argument("filters", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.command == "select":
            output = selection(args.suite, args.family, args.partition)
        elif args.command == "action-fixture":
            output = ["yes" if requires_action_fixture(args.filters) else "no"]
        elif args.command == "sync-server":
            output = ["yes" if requires_sync_server(args.filters) else "no"]
        else:
            output = ["yes" if requires_sync_peer(args.filters) else "no"]
    except ValueError as error:
        parser.error(str(error))
    print("\n".join(output))


if __name__ == "__main__":
    main()
