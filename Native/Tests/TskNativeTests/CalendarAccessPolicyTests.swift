import Foundation
import Testing
import TskCore
@testable import TskNative

@Test func calendarFreshGrantSurvivesUnpublishedStatusThroughTheCorePipelineWithoutCachingAccess() async throws {
    let source = CalendarPolicySource()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 1792144800) })
    let task = try await manager.create(TaskDraft(description: "Tasks remain available"))
    let unrequested = await manager.todayCalendar(from: source)
    #expect(unrequested.authorization == .notDetermined)
    #expect(unrequested.events.isEmpty)
    #expect(await source.counts() == [0, 0])
    let granted = await manager.todayCalendar(from: source, requestingAccess: true)
    #expect(granted.authorization == .fullAccess)
    #expect(granted.events.count == 1)
    #expect(await source.counts() == [5, 1])
    let refreshed = await manager.todayCalendar(from: source)
    #expect(refreshed.events.count == 1)
    #expect(await source.counts() == [9, 2])
    #expect(try await manager.tasks() == [task])
}

@Test func calendarRevalidationFailureNeverReadsOrCachesAnEarlierGrant() async throws {
    for failure in [CalendarPolicySource.Response.refused, .failed, .cancelled] {
        let source = CalendarPolicySource()
        try await source.requestReadAccess()
        await source.respond(failure)
        let attempt = Task { await source.authorization() }
        #expect(await attempt.value != .fullAccess)
        #expect(await source.counts() == [2, 0])
        await source.respond(.granted)
        #expect(await source.authorization() == .notDetermined)
        #expect(await source.counts() == [2, 0])
    }
}

@Test func calendarRevocationBeforeOrDuringReadDiscardsEventsWithoutPromptingAgain() async throws {
    for revoked in [EventKitAccessPublication.Authorization.denied, .restricted, .writeOnly, .unavailable] {
        for duringRead in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let manager = TaskChampionSession.makeManager(directory: directory)
            let task = try await manager.create(TaskDraft(description: "Ordinary task after revocation"))
            let source = CalendarPolicySource()
            try await source.requestReadAccess()
            await source.revoke(revoked, duringRead: duringRead)
            let snapshot = await manager.todayCalendar(from: source)
            #expect(snapshot.authorization != .fullAccess)
            #expect(snapshot.events.isEmpty)
            let counts = await source.counts()
            #expect(counts[1] == (duringRead ? 1 : 0))
            await source.resetPublication()
            #expect(await source.authorization() == .notDetermined)
            #expect(await source.counts() == counts)
            #expect(try await manager.tasks() == [task])
        }
    }
}

@Test @MainActor func failedFreshGrantCannotBeOverriddenByAConcurrentPublishedFullStatus() async throws {
    let access = EventKitAccessPolicy()
    var current = EventKitAccessPublication.Authorization.notDetermined
    #expect(try await access.requestAccess(authorization: { current }, request: { true }))
    let effective = await access.effectiveAuthorization(authorization: { current }, request: {
        current = .fullAccess
        return false
    })
    #expect(effective == .unavailable)
}

private actor CalendarPolicySource: CalendarEventSource {
    let access = EventKitAccessPolicy()
    var current = EventKitAccessPublication.Authorization.notDetermined
    var requests = 0
    var reads = 0
    enum Response { case granted, refused, failed, cancelled }
    var response = Response.granted
    var revokeDuringRead: EventKitAccessPublication.Authorization?

    func respond(_ value: Response) { response = value }
    func resetPublication() { current = .notDetermined }
    func revoke(_ value: EventKitAccessPublication.Authorization, duringRead: Bool) {
        if duringRead { revokeDuringRead = value } else { current = value }
    }

    func authorization() async -> CalendarReadAuthorization {
        let value = await access.effectiveAuthorization(authorization: { current }, request: request)
        switch value {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .fullAccess
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .writeOnly
        case .unavailable: return .unavailable
        }
    }

    func requestReadAccess() async throws {
        guard try await access.requestAccess(authorization: { current }, request: request) else { throw CocoaError(.fileReadNoPermission) }
    }

    func events(in window: DateInterval) async throws -> [CalendarEventSnapshot] {
        guard try await access.requireAccess(authorization: { current }, request: request) else { throw CocoaError(.fileReadNoPermission) }
        reads += 1
        if let revokeDuringRead { current = revokeDuringRead }
        let events = [CalendarEventSnapshot(calendarID: "owned", eventID: "today", title: "Display only", calendarTitle: "Owned", start: window.start, end: window.start.addingTimeInterval(3600))]
        guard try await access.requireAccess(authorization: { current }, request: request) else { throw CocoaError(.fileReadNoPermission) }
        return events
    }

    func request() throws -> Bool {
        requests += 1
        switch response {
        case .granted: return true
        case .refused: return false
        case .failed: throw CocoaError(.fileReadNoPermission)
        case .cancelled:
            withUnsafeCurrentTask { $0?.cancel() }
            return true
        }
    }
    func counts() -> [Int] { [requests, reads] }
}
