import Foundation
import TskCore

public struct LocalTaskSynchronizationReceiptStore: TaskSynchronizationReceiptStore {
    private let replica: TaskChampionReplica
    public init(directory: URL, library: String? = nil) { replica = TaskChampionReplica(directory: directory, library: library) }
    public func load() async throws -> TaskSynchronizationHistory? { try await replica.synchronizationHistory() }
}
