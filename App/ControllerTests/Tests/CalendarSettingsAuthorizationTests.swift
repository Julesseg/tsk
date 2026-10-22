import Foundation
import Testing
import TskCore
import TskNative

extension CalendarControllerProof {
    @Test func calendarSettingsRefreshesChangedAuthorizationOutsideTodayWithoutPrompting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CalendarSettingsSource()
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source)
        #expect(!controller.isDisplayingToday)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .fullAccess)
        await source.setAccess(.denied)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .denied)
        await source.setAccess(.fullAccess)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .fullAccess)
        #expect(await source.requests == 0)
        #expect(await source.reads == 2)
    }

    @Test func calendarSettingsPreservesReadFailureUntilExplicitRetryWhenAuthorizationIsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CalendarSettingsSource()
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source)
        await source.setFailure(true)
        await controller.refresh()
        #expect(controller.snapshot?.readError != nil)
        await source.setFailure(false)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.readError != nil)
        #expect(await source.reads == 1)
        await controller.refresh()
        #expect(controller.snapshot?.readError == nil)
        #expect(await source.reads == 2)
        #expect(await source.requests == 0)
    }

}

private actor CalendarSettingsSource: CalendarEventSource {
    var access = CalendarReadAuthorization.fullAccess
    var failing = false
    var requests = 0
    var reads = 0
    func authorization() -> CalendarReadAuthorization { access }
    func requestReadAccess() { requests += 1 }
    func setAccess(_ value: CalendarReadAuthorization) { access = value }
    func setFailure(_ value: Bool) { failing = value }
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] {
        reads += 1
        if failing { throw CocoaError(.fileReadUnknown) }
        return []
    }
}
