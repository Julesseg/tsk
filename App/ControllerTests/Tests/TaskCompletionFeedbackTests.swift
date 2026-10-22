import Foundation
import Testing
import TskCore
import TskNative

@MainActor private final class CompletionClock {
    let durations: AsyncStream<Duration>
    private let events: AsyncStream<Duration>.Continuation
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    init() { (durations, events) = AsyncStream.makeStream(of: Duration.self) }
    func pause(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            sleepers.append(continuation)
            events.yield(duration)
        }
    }
    func advance() { sleepers.removeFirst().resume() }
}

@MainActor @Test func completedUpcomingTaskSurvivesReloadUntilCheckedPauseAndCollapseFinish() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1792144800)
    let manager = TaskChampionSession.makeManager(directory: directory, now: { now })
    let task = try await manager.create(TaskDraft(description: "Finish release", attributes: ["scheduled": "1792231200", "due": "1792238400"]))
    let clock = CompletionClock()
    let feedback = TaskCompletionFeedback(pause: { await clock.pause($0) })
    let context = TaskCompletionFeedback.Context(query: .upcoming)
    var latest = [task]
    var pauses = clock.durations.makeAsyncIterator()
    let completing = Task {
        await feedback.complete(task: task, visibleTasks: latest, context: context, animated: true, shouldRemove: { !latest.contains { $0.id == task.id } }) {
            let saved = try? await manager.complete(id: task.id)
            latest = (try? await manager.viewSnapshot(query: .upcoming).tasks) ?? []
            return saved
        }
    }
    #expect(await pauses.next() == .seconds(1))
    #expect(try await manager.task(id: task.id).status == "completed")
    #expect(latest.isEmpty)
    #expect(feedback.phase(for: task.id, context: context) == .checked)
    let retained = feedback.visibleTasks(latest, context: context)
    #expect(retained == [task])
    #expect(UpcomingDay.groups(tasks: retained, at: now).flatMap(\.entries).count == 2)
    #expect(feedback.visibleTasks([], context: .init(query: .completed)).isEmpty)
    clock.advance()
    #expect(await pauses.next() == .milliseconds(280))
    #expect(feedback.phase(for: task.id, context: context) == .collapsing)
    #expect(feedback.visibleTasks(latest, context: context) == [task])
    clock.advance()
    #expect(await completing.value?.status == "completed")
    #expect(feedback.visibleTasks(latest, context: context).isEmpty)
    #expect(feedback.phase(for: task.id, context: context) == nil)
}

@MainActor @Test func consecutiveCompletionsKeepTheirPlaceAcrossReloadsAndIndependentRemoval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let first = try await manager.create(TaskDraft(description: "First"))
    let second = try await manager.create(TaskDraft(description: "Second"))
    let third = try await manager.create(TaskDraft(description: "Third"))
    let context = TaskCompletionFeedback.Context()
    let clock = CompletionClock()
    let feedback = TaskCompletionFeedback(pause: { await clock.pause($0) })
    var latest = [first, second, third]
    var pauses = clock.durations.makeAsyncIterator()
    func complete(_ task: TaskRecord) async -> TaskRecord? {
        await feedback.complete(task: task, visibleTasks: feedback.visibleTasks(latest, context: context), context: context, animated: false,
            shouldRemove: { !latest.contains { $0.id == task.id } }) {
            let saved = try? await manager.complete(id: task.id)
            latest.removeAll { $0.id == task.id }
            return saved
        }
    }
    let firstCompletion = Task { await complete(first) }
    #expect(await pauses.next() == .seconds(1))
    let secondCompletion = Task { await complete(second) }
    #expect(await pauses.next() == .seconds(1))
    #expect(feedback.visibleTasks(latest, context: context) == [first, second, third])
    clock.advance()
    _ = await firstCompletion.value
    #expect(feedback.visibleTasks(latest, context: context) == [second, third])
    #expect(feedback.phase(for: second.id, context: context) == .checked)
    clock.advance()
    _ = await secondCompletion.value
    #expect(feedback.visibleTasks(latest, context: context) == [third])
}

@MainActor @Test func failedOccurrenceCompletionRestoresTheOriginalRowWithoutCheckedFeedback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    let task = try await replica.create(id: UUID(), attributes: ["description": "Missing parent", "status": "pending", "parent": UUID().uuidString, "imask": "0", "due": "1792238400"])
    let manager = TaskChampionSession.makeManager(directory: directory)
    let feedback = TaskCompletionFeedback(pause: { _ in })
    let context = TaskCompletionFeedback.Context()
    let saved = await feedback.complete(task: task, visibleTasks: [task], context: context, animated: true, shouldRemove: { false }) {
        try? await manager.complete(id: task.id)
    }
    #expect(saved == nil)
    #expect(try await manager.task(id: task.id) == task)
    #expect(feedback.phase(for: task.id, context: context) == nil)
    #expect(feedback.visibleTasks([task], context: context) == [task])
}

@MainActor @Test func completedTaskThatStillMatchesTheViewStaysWithoutCollapsing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let task = try await manager.create(TaskDraft(description: "Retained in all statuses"))
    let clock = CompletionClock()
    let feedback = TaskCompletionFeedback(pause: { await clock.pause($0) })
    let context = TaskCompletionFeedback.Context(query: .all)
    var latest = [task]
    var pauses = clock.durations.makeAsyncIterator()
    let completing = Task {
        await feedback.complete(task: task, visibleTasks: latest, context: context, animated: true,
            shouldRemove: { !latest.contains { $0.id == task.id } }) {
            let saved = try? await manager.complete(id: task.id)
            latest = (try? await manager.viewSnapshot(query: .all).tasks) ?? []
            return saved
        }
    }
    #expect(await pauses.next() == .seconds(1))
    #expect(feedback.phase(for: task.id, context: context) == .checked)
    clock.advance()
    let saved = try #require(await completing.value)
    #expect(feedback.phase(for: task.id, context: context) == nil)
    #expect(feedback.visibleTasks(latest, context: context) == [saved])
}
