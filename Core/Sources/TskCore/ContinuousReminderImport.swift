import Foundation

public struct ReminderMoveCandidate: Sendable {
    public let snapshot: ReminderSnapshot
    private let remove: @Sendable () async throws -> Void
    public init(snapshot: ReminderSnapshot, removeSource: @escaping @Sendable () async throws -> Void) {
        self.snapshot = snapshot; remove = removeSource
    }
    public func removeSource() async throws { try await remove() }
}

public protocol ReminderMoveSource: ReminderSource {
    func moveCandidates(in listIDs: [String]) async throws -> [ReminderMoveCandidate]
}

public struct ReminderMoveResult: Sendable {
    public var imported: [TaskRecord] = []
    public var removedCount = 0
    public var skipped: [ReminderImportItem] = []
    public var failures: [ReminderImportItem] = []
    public var stopped: Bool { !failures.isEmpty }
}

public enum ContinuousReminderError: Error, LocalizedError, Sendable {
    case attemptInProgress
    case configurationUnavailable
    case deviceUnavailable
    public var errorDescription: String? {
        switch self {
        case .attemptInProgress: "A Reminders move is already running. Wait for its result."
        case .configurationUnavailable: "Device-local continuous Reminders settings are unavailable."
        case .deviceUnavailable: "This device could not be identified. Continuous import remains disabled."
        }
    }
}

public extension TaskManager {
    func moveReminders(from source: any ReminderMoveSource, mappings: [ReminderListMapping]) async throws -> ReminderMoveResult {
        guard !reminderMoveInProgress else { throw ContinuousReminderError.attemptInProgress }
        guard !mappings.isEmpty else { throw ReminderImportError.noLists }
        guard Set(mappings.map(\.listID)).count == mappings.count else { throw ReminderImportError.duplicateList }
        reminderMoveInProgress = true
        defer { reminderMoveInProgress = false }
        let candidates = try await source.moveCandidates(in: mappings.map(\.listID))
        var result = ReminderMoveResult()
        for candidate in candidates {
            guard let item = reminderImportItems([candidate.snapshot], mappings: mappings).first else { continue }
            guard let draft = item.draft else { result.skipped.append(item); continue }
            do {
                try Task.checkCancellation()
                result.imported.append(try await create(draft))
            } catch {
                result.failures.append(ReminderImportItem(title: item.title, draft: nil, reason: "Task was not saved; source was not removed. \(error.localizedDescription)"))
                break
            }
            do {
                try Task.checkCancellation()
                try await candidate.removeSource()
                result.removedCount += 1
            } catch {
                result.failures.append(ReminderImportItem(title: item.title, draft: nil, reason: "Task saved, but source removal failed. Automatic moves are paused. A retry can create a duplicate. \(error.localizedDescription)"))
                break
            }
        }
        return result
    }
}
