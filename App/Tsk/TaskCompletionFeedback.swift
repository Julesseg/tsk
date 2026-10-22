import Foundation
import Observation
import TskCore

@MainActor @Observable
final class TaskCompletionFeedback {
    struct Context: Equatable {
        var query: TaskQuery = .unfinished
        var project: TaskProjectSelection = .all
        var customViewID: UUID?
        var filter: UTF8String?
    }
    enum Phase { case saving, checked, covering, collapsing }
    private struct Entry {
        let task: TaskRecord
        let index: Int
        let preceding: [UUID]
        let following: [UUID]
        let context: Context
        var phase: Phase
    }
    private var entries: [UUID: Entry] = [:]
    private let pause: (Duration) async throws -> Void

    init(pause: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.pause = pause
    }

    func phase(for id: UUID, context: Context) -> Phase? {
        guard let entry = entries[id], entry.context == context else { return nil }
        return entry.phase
    }

    func removingIDs(context: Context) -> [UUID] {
        entries.filter { $0.value.context == context && $0.value.phase == .collapsing }.keys.sorted { $0.uuidString < $1.uuidString }
    }

    func visibleTasks(_ latest: [TaskRecord], context: Context) -> [TaskRecord] {
        let retained = entries.values.filter { $0.context == context && $0.phase != .collapsing }.sorted {
            $0.index == $1.index ? $0.task.id.uuidString < $1.task.id.uuidString : $0.index < $1.index
        }
        let ids = Set(retained.map { $0.task.id })
        var result = latest.filter { !ids.contains($0.id) }
        for entry in retained {
            let following = entry.following.lazy.compactMap { id in result.firstIndex { $0.id == id } }.first
            let preceding = entry.preceding.reversed().lazy.compactMap { id in result.firstIndex { $0.id == id } }.first
            result.insert(entry.task, at: following ?? preceding.map { $0 + 1 } ?? min(entry.index, result.count))
        }
        return result
    }

    func complete(task: TaskRecord, visibleTasks: [TaskRecord], context: Context, animated: Bool,
                  shouldRemove: () -> Bool, operation: () async -> TaskRecord?) async -> TaskRecord? {
        guard entries[task.id] == nil else { return nil }
        let index = visibleTasks.firstIndex { $0.id == task.id } ?? 0
        entries[task.id] = Entry(task: task, index: index, preceding: visibleTasks.prefix(index).map(\.id),
            following: visibleTasks.dropFirst(index + 1).map(\.id), context: context, phase: .saving)
        defer { entries[task.id] = nil }
        guard let saved = await operation() else { return nil }
        entries[task.id]?.phase = .checked
        do {
            if animated { try await pause(.milliseconds(400)) }
            try await pause(.seconds(1))
            if shouldRemove() {
                if animated {
                    entries[task.id]?.phase = .covering
                    try await pause(.milliseconds(420))
                }
                entries[task.id]?.phase = .collapsing
                if animated { try await pause(.milliseconds(240)) }
            }
        } catch {}
        return saved
    }
}
