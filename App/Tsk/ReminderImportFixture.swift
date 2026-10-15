#if DEBUG
import Foundation
import TskNative

@MainActor func prepareReminderFixture(source: EventKitReminderSource) async throws -> String? {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_FIXTURE"] else { return nil }
    guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { throw CocoaError(.userCancelled) }
    return try await EventKitReminderFixture.prepare(source: source, token: token)
    #else
    return nil
    #endif
}

@MainActor func cleanReminderFixtureIfRequested() throws {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_CLEANUP"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return }
    try EventKitReminderFixture.clean(source: EventKitReminderSource(), token: token)
    #endif
}

@MainActor func verifyReminderFixture(source: EventKitReminderSource) async throws -> String? {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_REMINDERS_FIXTURE"], environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return nil }
    return try await EventKitReminderFixture.verifySourcesUnchanged(source: source, token: token)
    #else
    return nil
    #endif
}
#endif
