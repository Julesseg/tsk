#if DEBUG
import Foundation
import TskNative

@MainActor func prepareReminderFixture(source: EventKitReminderSource) async throws -> String? {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    if let token = environment["TSK_TEST_REMINDERS_RECURRING_FIXTURE"] {
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { throw CocoaError(.userCancelled) }
        return try await EventKitRecurringReminderFixture.prepare(source: source, token: token)
    }
    guard let token = environment["TSK_TEST_REMINDERS_FIXTURE"] else { return nil }
    guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { throw CocoaError(.userCancelled) }
    return try await EventKitReminderFixture.prepare(source: source, token: token)
    #else
    return nil
    #endif
}

@MainActor func cleanReminderFixtureIfRequested() async throws {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_CLEANUP"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return }
    let source = EventKitReminderSource()
    do { try await EventKitReminderFixture.observeAuthorizationBeforeCleanup(source: source, token: token) }
    catch { NSLog("tsk owned Reminders authorization observation failed: %@", error.localizedDescription) }
    try EventKitReminderFixture.clean(source: source, token: token)
    #endif
}

@MainActor func verifyReminderFixture(source: EventKitReminderSource) async throws -> String? {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    if let token = environment["TSK_TEST_REMINDERS_RECURRING_FIXTURE"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" {
        return try await EventKitRecurringReminderFixture.verify(source: source, token: token, moved: false)
    }
    guard let token = environment["TSK_TEST_REMINDERS_FIXTURE"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return nil }
    return try await EventKitReminderFixture.verifySourcesUnchanged(source: source, token: token)
    #else
    return nil
    #endif
}

@MainActor func verifyContinuousReminderFixture(source: EventKitReminderSource) async throws -> String? {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    if let token = environment["TSK_TEST_REMINDERS_RECURRING_FIXTURE"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" {
        return try await EventKitRecurringReminderFixture.verify(source: source, token: token, moved: true)
    }
    guard let token = environment["TSK_TEST_REMINDERS_VERIFY_TOKEN"] ?? environment["TSK_TEST_REMINDERS_FIXTURE"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return nil }
    if environment["TSK_TEST_REMINDERS_EXPECT_PRESERVED"] == "1" { return try await EventKitReminderFixture.verifySourcesUnchanged(source: source, token: token) }
    return try await EventKitReminderFixture.verifyMove(source: source, token: token, changed: environment["TSK_TEST_REMINDERS_EXPECT_CHANGED"] == "1")
    #else
    return nil
    #endif
}

@MainActor func changeContinuousReminderFixture(source: EventKitReminderSource, edit: Bool) async throws {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_VERIFY_TOKEN"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { throw CocoaError(.userCancelled) }
    if edit { try await EventKitReminderFixture.editPendingIntoRecurring(source: source, token: token) }
    else { try EventKitReminderFixture.addCapture(source: source, token: token, title: "Observed fixture capture") }
    #endif
}

@MainActor func addForegroundReminderFixtureIfRequested() throws {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_ADD_ON_OPEN"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return }
    try EventKitReminderFixture.addCapture(source: EventKitReminderSource(), token: token, title: "Foreground fixture capture")
    #endif
}
#endif
