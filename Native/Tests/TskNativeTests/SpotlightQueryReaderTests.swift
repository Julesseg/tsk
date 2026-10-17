import Dispatch
import Foundation
import Testing
@testable import TskNative

@Suite struct SpotlightQueryReaderTests {
    @Test func missingCompletionTimesOutAndCancelsWithoutReturningPartialItems() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let read = Task { try await SpotlightQueryReader.read(timeoutNanoseconds: 1_000_000_000, request: native.request) }
        await native.waitForStart()
        native.found([1])
        await #expect(throws: SpotlightQueryReadError.self) { try await native.value(of: read) }
        await native.waitForCancel()
        #expect(native.cancelCount == 1)
        native.complete(nil)
        native.complete(NSError(domain: "late", code: 1))
    }

    @Test func completionPreservesEmptyAndBatchedItemsAndDoesNotCancelSuccess() async throws {
        for batches in [[], [[1], [2, 3]]] as [[[Int]]] {
            let native = ControlledSpotlightQuery()
            defer { native.finish() }
            let read = Task { try await SpotlightQueryReader.read(request: native.request) }
            await native.waitForStart()
            batches.forEach { native.found($0) }
            native.complete(nil)
            #expect(try await native.value(of: read) == batches.flatMap { $0 })
            native.found([99])
            native.complete(nil)
            read.cancel()
            #expect(native.cancelCount == 0)
        }
    }

    @Test func nativeFailurePreservesOriginalNSError() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let expected = NSError(domain: "owned.native.query", code: 37, userInfo: [NSLocalizedDescriptionKey: "Native search failed"])
        let read = Task { try await SpotlightQueryReader.read(request: native.request) }
        await native.waitForStart()
        native.complete(expected)
        do {
            _ = try await native.value(of: read)
            Issue.record("A native query error must not become successful empty results")
        } catch {
            let actual = error as NSError
            #expect(actual.domain == expected.domain && actual.code == expected.code)
            #expect(actual.localizedDescription == expected.localizedDescription)
            #expect(actual.userInfo as NSDictionary == expected.userInfo as NSDictionary)
        }
        #expect(native.cancelCount == 0)
    }

    @Test func callerCancellationCancelsOnceAndIgnoresLateCallbacks() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let read = Task { try await SpotlightQueryReader.read(request: native.request) }
        await native.waitForStart()
        read.cancel()
        await #expect(throws: CancellationError.self) { try await native.value(of: read) }
        await native.waitForCancel()
        native.found([1])
        native.complete(nil)
        read.cancel()
        #expect(native.cancelCount == 1)
    }

    @Test func preCancelledCallerDoesNotCreateOrStartOperation() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let read = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpotlightQueryReader.read(request: native.request)
        }
        await #expect(throws: CancellationError.self) { try await native.value(of: read) }
        #expect(!native.requested)
        #expect(native.startCount == 0 && native.cancelCount == 0)
    }

    @Test func cancellationBeforeOperationInstallationCancelsLateHandleWithoutStarting() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let native = ControlledSpotlightQuery(installationGate: gate)
        defer { native.finish() }
        let read = Task { try await SpotlightQueryReader.read(request: native.request) }
        await native.waitForRequest()
        read.cancel()
        await #expect(throws: CancellationError.self) { try await native.value(of: read) }
        gate.signal()
        await native.waitForCancel()
        #expect(native.startCount == 0 && native.cancelCount == 1)
    }

    @Test func timeoutBeforeOperationInstallationCancelsLateHandleWithoutStarting() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let native = ControlledSpotlightQuery(installationGate: gate)
        defer { native.finish() }
        let read = Task { try await SpotlightQueryReader.read(timeoutNanoseconds: 20_000_000, request: native.request) }
        await native.waitForRequest()
        await #expect(throws: SpotlightQueryReadError.self) { try await native.value(of: read) }
        gate.signal()
        await native.waitForCancel()
        #expect(native.startCount == 0 && native.cancelCount == 1)
    }

    @Test func timeoutReleasesCallerWhileNativeStartAndCancelRemainBlocked() async throws {
        let gate = DispatchSemaphore(value: 0)
        let cancelGate = DispatchSemaphore(value: 0)
        defer { gate.signal(); cancelGate.signal() }
        let native = ControlledSpotlightQuery(startGate: gate, cancelGate: cancelGate)
        defer { native.finish() }
        let read = Task { try await SpotlightQueryReader.read(timeoutNanoseconds: 1_000_000_000, request: native.request) }
        await native.waitForStart()
        await #expect(throws: SpotlightQueryReadError.self) { try await native.value(of: read) }
        await native.waitForCancel()
        #expect(native.cancelCount == 1)
        native.complete(nil)
    }

    @Test func synchronousCompletionBeforeOperationInstallationDoesNotStartOrCancel() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let read = Task {
            try await SpotlightQueryReader.read { found, completion in
                found([7])
                completion(nil)
                completion(NSError(domain: "duplicate", code: 1))
                return SpotlightQueryOperation(start: { Issue.record("Completed query must not start") }, cancel: { Issue.record("Successful query must not cancel") })
            }
        }
        #expect(try await native.value(of: read) == [7])
    }

    @Test func synchronousCompletionDuringStartDoesNotCancel() async throws {
        let native = ControlledSpotlightQuery()
        defer { native.finish() }
        let read = Task {
            try await SpotlightQueryReader.read { found, completion in
                SpotlightQueryOperation(start: { found([7]); completion(nil); completion(nil) }, cancel: { Issue.record("Successful query must not cancel") })
            }
        }
        #expect(try await native.value(of: read) == [7])
    }

    @Test func concurrentCompletionAndCancellationHaveOneTerminalOutcome() async throws {
        for _ in 0..<100 {
            let native = ControlledSpotlightQuery()
            defer { native.finish() }
            let read = Task { try await SpotlightQueryReader.read(request: native.request) }
            await native.waitForStart()
            native.found([1, 2])
            await withTaskGroup(of: Void.self) { group in
                group.addTask { native.complete(nil) }
                group.addTask { read.cancel() }
            }
            do { #expect(try await native.value(of: read) == [1, 2]) }
            catch { #expect(error is CancellationError) }
            native.complete(nil)
            native.found([3])
            #expect(native.cancelCount <= 1)
        }
    }
}

private final class ControlledSpotlightQuery: @unchecked Sendable {
    private let lock = NSLock()
    private let installationGate: DispatchSemaphore?
    private let startGate: DispatchSemaphore?
    private let cancelGate: DispatchSemaphore?
    private var foundHandler: (@Sendable ([Int]) -> Void)?
    private var completion: (@Sendable ((any Error)?) -> Void)?
    private var starts = 0
    private var cancels = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultWaiters: [UUID: CheckedContinuation<Result<[Int], any Error>, Never>] = [:]
    private var expired = false
    private var cleanup: Task<Void, Never>?

    init(installationGate: DispatchSemaphore? = nil, startGate: DispatchSemaphore? = nil, cancelGate: DispatchSemaphore? = nil) {
        self.installationGate = installationGate
        self.startGate = startGate
        self.cancelGate = cancelGate
        cleanup = Task.detached { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
            self?.expire()
        }
    }

    func finish() { cleanup?.cancel() }

    func value(of read: Task<[Int], any Error>) async throws -> [Int] {
        let id = UUID()
        let result = await withCheckedContinuation { continuation in
            let expired = lock.withLock {
                guard !self.expired else { return true }
                resultWaiters[id] = continuation
                return false
            }
            if expired { continuation.resume(returning: .failure(QueryTestDeadline())) }
            else {
                Task.detached {
                    let result = await read.result
                    self.lock.withLock { self.resultWaiters.removeValue(forKey: id) }?.resume(returning: result)
                }
            }
        }
        return try result.get()
    }

    private func expire() {
        let (waiters, results, completion) = lock.withLock {
            expired = true
            let waiters = requestWaiters + startWaiters + cancelWaiters
            let results = Array(resultWaiters.values)
            requestWaiters = []; startWaiters = []; cancelWaiters = []; resultWaiters = [:]
            return (waiters, results, self.completion)
        }
        Issue.record("Query callback test exceeded its five-second cleanup deadline")
        waiters.forEach { $0.resume() }
        results.forEach { $0.resume(returning: .failure(QueryTestDeadline())) }
        completion?(QueryTestDeadline())
        installationGate?.signal(); startGate?.signal(); cancelGate?.signal()
    }

    var requested: Bool { lock.withLock { completion != nil } }
    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func request(_ found: @escaping @Sendable ([Int]) -> Void, _ completion: @escaping @Sendable ((any Error)?) -> Void) -> SpotlightQueryOperation {
        let waiters = lock.withLock {
            foundHandler = found
            self.completion = completion
            let waiters = requestWaiters
            requestWaiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
        if let installationGate, installationGate.wait(timeout: .now() + 5) != .success { Issue.record("Test did not release query installation") }
        return SpotlightQueryOperation(start: {
            let waiters = self.lock.withLock {
                self.starts += 1
                let waiters = self.startWaiters
                self.startWaiters = []
                return waiters
            }
            waiters.forEach { $0.resume() }
            if let gate = self.startGate, gate.wait(timeout: .now() + 5) != .success { Issue.record("Test did not release query start") }
        }, cancel: {
            let waiters = self.lock.withLock {
                self.cancels += 1
                let waiters = self.cancelWaiters
                self.cancelWaiters = []
                return waiters
            }
            waiters.forEach { $0.resume() }
            if let gate = self.cancelGate, gate.wait(timeout: .now() + 5) != .success { Issue.record("Test did not release query cancellation") }
        })
    }

    func found(_ items: [Int]) { lock.withLock { foundHandler }?(items) }
    func complete(_ error: (any Error)?) { lock.withLock { completion }?(error) }

    func waitForRequest() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if completion != nil || expired { return true }
                requestWaiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func waitForStart() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if starts > 0 || expired { return true }
                startWaiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func waitForCancel() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if cancels > 0 || expired { return true }
                cancelWaiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

private struct QueryTestDeadline: Error {}
