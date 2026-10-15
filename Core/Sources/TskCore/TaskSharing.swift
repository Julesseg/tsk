import Foundation

public enum SharedTaskItem: Sendable {
    case text(String)
    case url(URL)
}

public struct SharedTaskDraft: Equatable, Sendable {
    public var task: TaskDraft
    public var content: String

    public init(task: TaskDraft, content: String) { self.task = task; self.content = content }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.task == rhs.task && lhs.content.matchesBytes(rhs.content) }
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
    static func sharedDraft(from items: [SharedTaskItem]) throws -> SharedTaskDraft {
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
        guard let first = fragments.first else { throw TaskSharingError.noSupportedContent }
        let title = first.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? first
        return SharedTaskDraft(task: TaskDraft(description: title.trimmingCharacters(in: .whitespaces)), content: fragments.joined(separator: "\n\n"))
    }

    func captureSharedTask(_ shared: SharedTaskDraft) async throws -> TaskRecord {
        var draft = shared.task
        if !shared.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let instant = now().timeIntervalSince1970
            guard instant.isFinite, let initial = Int64(exactly: instant.rounded(.towardZero)), initial > 0 else { throw TaskManagementError.invalidAnnotationTimestamp }
            var timestamp = initial
            while draft.attributes["annotation_\(timestamp)"] != nil {
                let next = timestamp.addingReportingOverflow(1)
                guard !next.overflow else { throw TaskManagementError.invalidAnnotationTimestamp }
                timestamp = next.partialValue
            }
            draft.attributes["annotation_\(timestamp)"] = shared.content
        }
        return try await create(draft)
    }
}
