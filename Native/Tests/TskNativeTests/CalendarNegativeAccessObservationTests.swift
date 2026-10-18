import Foundation
import Testing
import TskCore
@testable import TskNative

@Suite @MainActor struct CalendarNegativeAccessObservationTests {
    @Test func completedRefusalRemainsDeniedAcrossUnpublishedRefreshesWithoutRequestingOrReading() async throws {
        let access = EventKitCalendarAccessObservation()
        var requests = 0
        let request = { requests += 1; return false }
        #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: request) == .notDetermined)
        #expect(requests == 0)
        #expect(try await !access.requestAccess(authorization: { .notDetermined }, request: request))
        for _ in 0..<3 {
            #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: request) == .denied)
            #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: request))
        }
        #expect(requests == 1)
    }

    @Test func publishedFullAccessClearsOnlyTheNegativeObservationWithoutCachingAReadGrant() async throws {
        let access = EventKitCalendarAccessObservation()
        var current = EventKitAccessPublication.Authorization.notDetermined
        var requests = 0
        let request = { requests += 1; return false }
        #expect(try await !access.requestAccess(authorization: { current }, request: request))
        current = .fullAccess
        #expect(await access.effectiveAuthorization(authorization: { current }, request: request) == .fullAccess)
        current = .notDetermined
        #expect(await access.effectiveAuthorization(authorization: { current }, request: request) == .notDetermined)
        #expect(try await !access.requireAccess(authorization: { current }, request: request))
        #expect(requests == 1)
    }

    @Test func explicitNewGrantRecoversButEveryUnpublishedOperationStillNeedsItsOwnGrant() async throws {
        let access = EventKitCalendarAccessObservation()
        var requests = 0
        #expect(try await !access.requestAccess(authorization: { .notDetermined }, request: { requests += 1; return false }))
        #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { requests += 1; return true }) == .denied)
        #expect(requests == 1)
        #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { requests += 1; return true }))
        #expect(try await access.requireAccess(authorization: { .notDetermined }, request: { requests += 1; return true }))
        #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { requests += 1; return true }) == .fullAccess)
        #expect(requests == 4)
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: { requests += 1; return false }))
        #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { requests += 1; return true }) == .denied)
        #expect(requests == 5)
    }

    @Test func requestErrorsAndCancellationDoNotCreateOrRetainANewRefusal() async throws {
        enum RequestFailure: Error { case failed }
        let failed = EventKitCalendarAccessObservation()
        #expect(try await !failed.requestAccess(authorization: { .notDetermined }, request: { false }))
        await #expect(throws: RequestFailure.self) {
            try await failed.requestAccess(authorization: { .notDetermined }, request: { throw RequestFailure.failed })
        }
        #expect(await failed.effectiveAuthorization(authorization: { .notDetermined }, request: { false }) == .notDetermined)
        let previouslyRefused = EventKitCalendarAccessObservation()
        #expect(try await !previouslyRefused.requestAccess(authorization: { .notDetermined }, request: { false }))
        let cancelledRetry = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await previouslyRefused.requestAccess(authorization: { .notDetermined }, request: { Issue.record("Cancelled request must not prompt"); return false })
        }
        await #expect(throws: CancellationError.self) { try await cancelledRetry.value }
        #expect(await previouslyRefused.effectiveAuthorization(authorization: { .notDetermined }, request: { false }) == .notDetermined)
        for cancellationPhase in 0...2 {
            let access = EventKitCalendarAccessObservation()
            var requests = 0
            let operation = Task { @MainActor in
                if cancellationPhase == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                var samples = 0
                return try await access.requestAccess(authorization: {
                    samples += 1
                    if cancellationPhase == 2 && samples == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                    return .notDetermined
                }, request: {
                    requests += 1
                    if cancellationPhase == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                    return false
                })
            }
            await #expect(throws: CancellationError.self) { try await operation.value }
            #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { false }) == .notDetermined)
            #expect(requests == (cancellationPhase == 0 ? 0 : 1))
        }
    }

    @Test func failedRevalidationIsUnavailableAndKnownRevocationStillPreventsAllRequests() async throws {
        enum RequestFailure: Error { case failed }
        let access = EventKitCalendarAccessObservation()
        #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
        #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { throw RequestFailure.failed }) == .unavailable)
        for current in [EventKitAccessPublication.Authorization.denied, .restricted, .writeOnly, .unavailable] {
            let access = EventKitCalendarAccessObservation()
            #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
            var requests = 0
            #expect(try await !access.requireAccess(authorization: { current }, request: { requests += 1; return true }))
            #expect(await access.effectiveAuthorization(authorization: { .notDetermined }, request: { requests += 1; return true }) == .notDetermined)
            #expect(requests == 0)
        }
    }

    @Test func corePublishesCompletedRefusalWithoutReadErrorAndKeepsOrdinaryRefreshDenied() async throws {
        let source = CalendarObservedPermissionSource()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TaskChampionSession.makeManager(directory: directory)
        let task = try await manager.create(TaskDraft(description: "Ordinary task remains available"))
        let declined = await manager.todayCalendar(from: source, requestingAccess: true)
        #expect(declined.authorization == .denied)
        #expect(declined.readError == nil)
        #expect(declined.events.isEmpty)
        let refreshed = await manager.todayCalendar(from: source)
        #expect(refreshed.authorization == .denied)
        #expect(refreshed.readError == nil)
        #expect(refreshed.events.isEmpty)
        #expect(await source.counts() == [1, 0])
        await source.respond(.failed)
        let failed = await manager.todayCalendar(from: source, requestingAccess: true)
        #expect(failed.authorization == .notDetermined)
        #expect(failed.readError != nil)
        #expect(await source.counts() == [2, 0])
        await source.respond(.granted)
        let granted = await manager.todayCalendar(from: source, requestingAccess: true)
        #expect(granted.authorization == .fullAccess)
        #expect(granted.readError == nil)
        #expect(await source.counts() == [7, 1])
        #expect(try await manager.tasks() == [task])
    }
}

private actor CalendarObservedPermissionSource: CalendarEventSource {
    private let access = EventKitCalendarAccessObservation()
    private var requests = 0
    private var reads = 0
    enum Response { case refused, failed, granted }
    private var response = Response.refused

    func respond(_ value: Response) { response = value }
    func counts() -> [Int] { [requests, reads] }

    func authorization() async -> CalendarReadAuthorization {
        switch await access.effectiveAuthorization(authorization: { .notDetermined }, request: request) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        case .unavailable: .unavailable
        }
    }

    func requestReadAccess() async throws {
        guard try await access.requestAccess(authorization: { .notDetermined }, request: request) else { throw CocoaError(.fileReadNoPermission) }
    }

    func events(in window: DateInterval) async throws -> [CalendarEventSnapshot] {
        guard try await access.requireAccess(authorization: { .notDetermined }, request: request) else { throw CocoaError(.fileReadNoPermission) }
        reads += 1
        guard try await access.requireAccess(authorization: { .notDetermined }, request: request) else { throw CocoaError(.fileReadNoPermission) }
        return []
    }

    private func request() throws -> Bool {
        requests += 1
        return switch response {
        case .refused: false
        case .granted: true
        case .failed: throw CocoaError(.fileReadNoPermission)
        }
    }
}
