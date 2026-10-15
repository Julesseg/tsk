import Foundation
import Testing
import TskCore
import TskNative

enum CalendarCaller { @TaskLocal static var passive = false }
@MainActor enum TaskUIBoundaryDiagnostics {
    static var signal: ControllerSignal?
    static var ownerPublished: (() -> Void)?
    static func event(_ stage: String, details: [String: String]) {
        if !CalendarCaller.passive, stage == "calendar.refresh.published", let callback = ownerPublished {
            ownerPublished = nil
            callback()
        }
        if CalendarCaller.passive && ["calendar.refresh.published", "calendar.refresh.coalesced"].contains(stage) { signal?.signal() }
    }
}
@MainActor final class ControllerSignal {
    var didSignal = false
    var continuation: CheckedContinuation<Void, Never>?
    func signal() { didSignal = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if didSignal { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
actor CalendarProofSource: CalendarEventSource {
    enum Failure: LocalizedError { case notReady; var errorDescription: String? { "Access granted but not ready. Try again." } }
    var access = CalendarReadAuthorization.notDetermined
    var permission: CheckedContinuation<Void, Never>?
    var permissionStarted = false
    var permissionObservers: [CheckedContinuation<Void, Never>] = []
    var requestCount = 0
    var values: [CalendarEventSnapshot] = []
    var failure = false
    var eventReads = 0
    var holdFinalAuthorization = false
    var heldFinalAuthorization = false
    var finalAuthorization: CheckedContinuation<Void, Never>?
    var finalAuthorizationObservers: [CheckedContinuation<Void, Never>] = []
    func authorization() async -> CalendarReadAuthorization {
        if holdFinalAuthorization, eventReads == 1, !heldFinalAuthorization {
            heldFinalAuthorization = true
            finalAuthorizationObservers.forEach { $0.resume() }; finalAuthorizationObservers.removeAll()
            await withCheckedContinuation { finalAuthorization = $0 }
        }
        return access
    }
    func requestReadAccess() async throws {
        requestCount += 1; permissionStarted = true
        permissionObservers.forEach { $0.resume() }; permissionObservers.removeAll()
        await withCheckedContinuation { permission = $0 }
        if failure { throw Failure.notReady }
    }
    func events(in window: DateInterval) -> [CalendarEventSnapshot] { eventReads += 1; return values }
    func setEvent(_ title: String, holdFinalRead: Bool = false) {
        let start = Date(timeIntervalSince1970: 1792144800)
        values = [CalendarEventSnapshot(calendarID: "owned", eventID: "event", title: title, calendarTitle: "Owned", start: start, end: start.addingTimeInterval(900))]
        holdFinalAuthorization = holdFinalRead
    }
    func waitForFinalAuthorization() async {
        if heldFinalAuthorization { return }
        await withCheckedContinuation { finalAuthorizationObservers.append($0) }
    }
    func releaseFinalAuthorization() { finalAuthorization?.resume(); finalAuthorization = nil }
    func waitForRequest() async {
        if permissionStarted { return }
        await withCheckedContinuation { permissionObservers.append($0) }
    }
    func release(failing: Bool) {
        failure = failing
        if !failing { access = .fullAccess }
        permission?.resume(); permission = nil
    }
}

@Suite(.serialized) @MainActor struct CalendarControllerProof {
    @Test func foregroundRefreshMustNotDiscardARequestThatBecomesReady() async throws {
        try await scenario(failing: false)
    }
    @Test func foregroundRefreshMustNotDiscardOrClearRequestNotReadyError() async throws {
        try await scenario(failing: true)
    }
    @Test func sourceChangeAfterEventReadGetsOneFreshSuccessfulFollowup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 1792144800) })
        let source = CalendarProofSource()
        await source.setEvent("old", holdFinalRead: true)
        let controller = TodayCalendarController(manager: manager, source: source)
        let signal = ControllerSignal(); TaskUIBoundaryDiagnostics.signal = signal
        defer { TaskUIBoundaryDiagnostics.signal = nil }
        let requesting = Task { await controller.refresh(requestingAccess: true) }
        await source.waitForRequest()
        await source.release(failing: false)
        await source.waitForFinalAuthorization()
        await source.setEvent("new")
        let foreground = Task { await CalendarCaller.$passive.withValue(true) { await controller.refresh() } }
        await signal.wait()
        await source.releaseFinalAuthorization()
        await requesting.value; await foreground.value
        #expect(controller.snapshot?.events.map(\.event.title) == ["new"])
        #expect(await source.eventReads == 2)
        #expect(await source.requestCount == 1)
    }

    @Test func canceledPassiveRefreshDoesNotCancelOwnerOrStartAnotherRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TaskChampionSession.makeManager(directory: directory)
        let source = CalendarProofSource()
        let controller = TodayCalendarController(manager: manager, source: source)
        let signal = ControllerSignal(); TaskUIBoundaryDiagnostics.signal = signal
        defer { TaskUIBoundaryDiagnostics.signal = nil }
        let requesting = Task { await controller.refresh(requestingAccess: true) }
        await source.waitForRequest()
        let foreground = Task { await CalendarCaller.$passive.withValue(true) { await controller.refresh() } }
        await signal.wait()
        foreground.cancel()
        await foreground.value
        #expect(controller.isLoading)
        #expect(!requesting.isCancelled)
        await source.release(failing: false)
        await requesting.value
        #expect(controller.snapshot?.authorization == .fullAccess)
        #expect(await source.eventReads == 1)
        #expect(await source.requestCount == 1)
    }

    @Test func passiveCancellationDuringOwnerPublicationPreventsFollowupBeforeQueuedCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CalendarProofSource()
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source)
        let signal = ControllerSignal(); TaskUIBoundaryDiagnostics.signal = signal
        defer { TaskUIBoundaryDiagnostics.signal = nil; TaskUIBoundaryDiagnostics.ownerPublished = nil }
        let requesting = Task { await controller.refresh(requestingAccess: true) }
        await source.waitForRequest()
        let foreground = Task { await CalendarCaller.$passive.withValue(true) { await controller.refresh() } }
        await signal.wait()
        TaskUIBoundaryDiagnostics.ownerPublished = { foreground.cancel() }
        await source.release(failing: false)
        await requesting.value; await foreground.value
        #expect(!requesting.isCancelled)
        #expect(controller.snapshot?.authorization == .fullAccess)
        #expect(await source.eventReads == 1)
    }

    private func scenario(failing: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TaskChampionSession.makeManager(directory: directory)
        let source = CalendarProofSource()
        let controller = TodayCalendarController(manager: manager, source: source)
        let signal = ControllerSignal(); TaskUIBoundaryDiagnostics.signal = signal
        defer { TaskUIBoundaryDiagnostics.signal = nil }
        let requesting = Task { await controller.refresh(requestingAccess: true) }
        await source.waitForRequest()
        let foreground = Task { await CalendarCaller.$passive.withValue(true) { await controller.refresh() } }
        await signal.wait()
        await source.release(failing: failing)
        await requesting.value
        await foreground.value
        #expect(await source.requestCount == 1)
        #expect(!controller.isLoading)
        if failing {
            #expect(controller.snapshot?.authorization == .notDetermined)
            #expect(controller.snapshot?.readError?.contains("not ready") == true)
        } else {
            #expect(controller.snapshot?.authorization == .fullAccess)
            #expect(controller.snapshot?.readError == nil)
        }
    }
}
