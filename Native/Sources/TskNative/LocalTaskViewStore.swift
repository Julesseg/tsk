import Foundation
import TskCore

public actor LocalTaskViewStore: TaskViewDefinitionsStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("saved-task-views.json") }

    public init(directory: URL) { self.directory = directory }

    public static func directory(testName: String? = nil) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var directory = support.appendingPathComponent("tsk-local-views", isDirectory: true)
        if let testName { directory.appendPathComponent("ui-tests/\(testName)", isDirectory: true) }
        return directory
    }

    public func load() throws -> [SavedTaskView] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([SavedTaskView].self, from: Data(contentsOf: file))
    }

    public func save(_ definitions: [SavedTaskView]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(definitions)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
