import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable final class TodayCalendarController {
    let manager: TaskManager
    let source: any CalendarEventSource
    private(set) var snapshot: TodayCalendarSnapshot?
    private(set) var isLoading = false
    private(set) var fixtureError: String?
    private(set) var fixtureVerified = false
    var isDisplayingToday = false
    private var generation = UUID()
    private var refreshTask: Task<Void, Never>?
    private var preparedFixture = false

    init(manager: TaskManager, source: any CalendarEventSource = EventKitCalendarSource()) {
        self.manager = manager
        #if DEBUG
        if ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_READ_FAILURE"] == "1" {
            self.source = FailingCalendarFixtureSource(source: source)
        } else { self.source = source }
        #else
        self.source = source
        #endif
    }

    func refresh(requestingAccess: Bool = false) async {
        let request = UUID(); generation = request; isLoading = true
        var value = await manager.todayCalendar(from: source, requestingAccess: requestingAccess)
        #if DEBUG && targetEnvironment(simulator)
        if value.authorization == .fullAccess, !preparedFixture,
           let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_FIXTURE"],
           ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let day = value.day {
            preparedFixture = true
            do { try await EventKitCalendarFixture.prepare(token: token, day: day); value = await manager.todayCalendar(from: source) }
            catch { fixtureError = error.localizedDescription }
        }
        if value.authorization == .fullAccess, let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_FIXTURE"],
           ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let day = value.day {
            do { try await EventKitCalendarFixture.verify(token: token, day: day, displayed: value.events.map(\.event)); fixtureVerified = true }
            catch { fixtureError = error.localizedDescription }
        }
        #endif
        guard request == generation else { return }
        snapshot = value; isLoading = false
    }

    func sourceChanged() {
        guard isDisplayingToday else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await refresh() } catch {}
        }
    }
}

#if DEBUG
private struct FailingCalendarFixtureSource: CalendarEventSource {
    let source: any CalendarEventSource
    func authorization() async -> CalendarReadAuthorization { await source.authorization() }
    func requestReadAccess() async throws { try await source.requestReadAccess() }
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] { throw CalendarFixtureReadFailure() }
}
private struct CalendarFixtureReadFailure: LocalizedError {
    var errorDescription: String? { "Injected Calendar adapter read failure. Tasks remain available." }
}
#endif
