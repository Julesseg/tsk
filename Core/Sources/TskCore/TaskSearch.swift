import Foundation

extension TaskManager {
    public func findTasks(matching text: String, query: TaskQuery = .unfinished) async throws -> [TaskRecord] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await tasks(query: query).filter { term.isEmpty || $0.description.localizedCaseInsensitiveContains(term) }
    }
}
