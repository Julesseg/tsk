import argparse
import importlib.util
import pathlib
import re


PHONE_SMOKE = (
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
    'TaskBulkSelectionUITests/testContinuousSelectionFreezesRowsBeforeReleaseAndCompletesDurably',
)

NIGHTLY = (
    'AutomaticSynchronizationUITests/testAutomaticFailureKeepsCaptureAvailableAndRetriesOnRelaunch',
    'CalendarTodayUITests/testRealCalendarTodayReadOnlyClippingStoreChangeForegroundAndRevocation',
    'ContinuousReminderImportUITests/testActualSourceEditIntoRecurringRuleIsPreservedAndAutomaticMovePauses',
    'ContinuousReminderImportUITests/testInterruptionAndActualPermissionResetAfterCommitLeaveSourceAndTaskAvailable',
    'ContinuousReminderImportUITests/testRealContinuousMoveSourceChangesForegroundRescanAndDurableReopen',
    'CustomViewsUITests/testRawViewValidationSaveEditReopenResultsActionsAndDeletion',
    'MissedNotificationUITests/testRealEncryptedFinalStateDeliversNewMissedOnceAndCancelsReceivedCompletion',
    'ReminderImportUITests/testRealEventKitCopyAndRecurrenceFixturePreserveSourcesAndDurableTasks',
    'ReminderRecurrenceUITests/testActualCurrentWeeklyMoveRemovesOnlyVerifiedRemainderAfterDurableTemplateSave',
    'SeriesMetadataUITests/testSeriesMetadataPreviewCancelSaveAndPersistentFutureOccurrences',
    'SeriesTransitionUITests/testExplicitSuccessorPreviewCancelCommitAndRetiredHistoryRemainSeparate',
    'ShareCaptureUITests/testSharingTextAndLinksCreatesPlainTasksWithoutAnEditor',
    'SpotlightUITests/testSystemSpotlightOpensExactTaskAndLocalCompletionRemovesIndexEntry',
    'SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer',
    'TaskAddURLUITests/testActualCallbackDeliveryPreservesArgumentsAndDurableUUIDResultAndReportsInvalidInput',
    'TaskAddURLUITests/testCompleteOccurrenceURLPersistsAndMissingDeletedTargetsReturnErrors',
    'TaskAddURLUITests/testCompleteURLReturnsRichSavedTaskRevealsItAndProtectsNestedDrafts',
    'TaskAddURLUITests/testURLSavesValidDraftAndRetainsInvalidDraftWithoutCreatingTask',
    'TaskBulkSelectionUITests/testBulkDateFailureRetainsPendingOperationAndEverySelectedTask',
    'TaskBulkSelectionUITests/testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch',
    'TaskBulkSelectionUITests/testContinuousSelectionFreezesRowsBeforeReleaseAndCompletesDurably',
    'TaskBulkSelectionUITests/testSelectionResolvesValidEditorAndRetainsInvalidDraft',
    'TaskKeyboardCompatibilityUITests/testWorkspaceAndEditorCommandsKeepOwnershipAcrossFocus',
    'TaskNotificationUITests/testActualClosedAppDeliveryAndLocalMutationReconciliation',
    'TaskPresentationUITests/testOccurrenceCircleCompletionAndGenuineFailureKeepSeriesScope',
    'TaskRowEditingUITests/testDependencyLinksSaveSourceAndExpandTargetWithReturnRoute',
    'TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening',
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion',
    'TaskRowEditingUITests/testSupportingInformationEditsKeepTheExpandedDraftAndPersist',
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch',
    'WidgetUITests/testInstalledWidgetRendersTodayCompletesAndUsesSavedViewWithTruthfulDeletionError',
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
    'SpotlightUITests/testStaleRealSystemResultReportsUnavailableAndNeverOpensAnotherTask',
    'SynchronizationUITests/testConnectionValidationPersistenceAndServerFailureRetainOfflineTask',
    'TaskActivityUITests/testOrdinaryTaskInformationStartStopPersistentReopenAndCompletionClearActiveState',
    'TaskAddURLUITests/testOversizedResultAndFailedDeliveryKeepExactlyOneDurableTaskPerAdd',
    'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations',
    'TaskBulkSelectionUITests/testSelectionPickerValueChangesKeepQuickActionsStationary',
    'TaskNotificationUITests/testActualPermissionRevocationStillAllowsDurableTaskCreation',
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
KEYBOARD = (
    "TaskKeyboardCompatibilityUITests/testWorkspaceAndEditorCommandsKeepOwnershipAcrossFocus",
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
)
TEXT = (
    "ShareCaptureUITests/testSharingTextAndLinksCreatesPlainTasksWithoutAnEditor",
    "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations",
    "SeriesTransitionUITests/testExplicitSuccessorPreviewCancelCommitAndRetiredHistoryRemainSeparate",
)
MENU = (
    "TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
    "TaskRowEditingUITests/testNativeProjectMenuDismissesTitleAndNoteKeyboard",
    "TaskRowEditingUITests/testNativeProjectMenuRetainsScrolledPositionWhileOpen",
    *KEYBOARD,
)
REGRESSION = (
    "ShareCaptureUITests/testSharingTextAndLinksCreatesPlainTasksWithoutAnEditor",
    "TaskRowEditingUITests/testNativeProjectMenuActionsSurviveRepeatedPopoverDismissal",
    "TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion",
    "TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening",
    "WorkspaceSettingsUITests/testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch",
)
SUITES = dict(smoke=PHONE_SMOKE, full=NIGHTLY, diagnostic=DIAGNOSTIC,
              keyboard=KEYBOARD, text=TEXT, menu=MENU, regression=REGRESSION)
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


def phases(filters):
    selected = selected_methods(filters)
    if not selected:
        raise ValueError("Selection contains no UI tests")
    share = {test for test in selected if matches(test, "TskUITests/ShareCaptureUITests")}
    return [phase for phase, enabled in (("share", share), ("main", selected - share)) if enabled]


def requires_sync_peer(filters):
    return "TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer" in selected_methods(filters)


def requires_sync_server(filters):
    return bool(selected_methods(filters) & {
        "TskUITests/SynchronizationUITests/testSuccessfulManualSynchronizationUsesRealConfiguredServer",
        "TskUITests/MissedNotificationUITests/testRealEncryptedFinalStateDeliversNewMissedOnceAndCancelsReceivedCompletion",
    })


def requires_native_keyboard(filters):
    selected_methods(filters)
    spec = importlib.util.spec_from_file_location("native_keyboard_owner", pathlib.Path(__file__).with_name("with-native-keyboard-hid.py"))
    owner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(owner)
    return bool(owner.selected_cases(filters))


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("select")
    select.add_argument("suite", choices=("smoke", "full", "diagnostic", "keyboard", "text", "regression", "menu"))
    select.add_argument("family", choices=("iPhone",))
    select.add_argument("--partition", choices=("all", "workspace", "row-editing"), default="all")
    phase = commands.add_parser("phases")
    phase.add_argument("filters", nargs=argparse.REMAINDER)
    peer = commands.add_parser("sync-peer")
    peer.add_argument("filters", nargs=argparse.REMAINDER)
    server = commands.add_parser("sync-server")
    server.add_argument("filters", nargs=argparse.REMAINDER)
    native = commands.add_parser("native-keyboard")
    native.add_argument("filters", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.command == "select":
            output = selection(args.suite, args.family, args.partition)
        elif args.command == "phases":
            output = phases(args.filters)
        elif args.command == "native-keyboard":
            output = ["yes" if requires_native_keyboard(args.filters) else "no"]
        elif args.command == "sync-server":
            output = ["yes" if requires_sync_server(args.filters) else "no"]
        else:
            output = ["yes" if requires_sync_peer(args.filters) else "no"]
    except ValueError as error:
        parser.error(str(error))
    print("\n".join(output))


if __name__ == "__main__":
    main()
