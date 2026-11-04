import Foundation

public enum SharedTaskItem: Sendable {
    case text(String)
    case url(URL)
}

public enum TaskSharingError: Error, Equatable, LocalizedError, Sendable {
    case noSupportedContent
    case fileURL

    public var errorDescription: String? {
        switch self {
        case .noSupportedContent: "Share text or a link to create a task. File attachments are not supported."
        case .fileURL: "File attachments cannot be saved as tasks. Share text or a web link instead."
        }
    }
}

public extension TaskManager {
    static func sharedDescription(from items: [SharedTaskItem]) throws -> String {
        var fragments: [String] = []
        for item in items {
            let text: String
            switch item {
            case .text(let value): text = value
            case .url(let value):
                guard !value.isFileURL else { throw TaskSharingError.fileURL }
                text = value.absoluteString
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fragments.append(text) }
        }
        let description = fragments.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw TaskSharingError.noSupportedContent }
        return description
    }

    func captureSharedTask(_ items: [SharedTaskItem]) async throws -> TaskRecord {
        try await create(TaskDraft(description: Self.sharedDescription(from: items)))
    }
}
