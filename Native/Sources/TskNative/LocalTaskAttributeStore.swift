import Foundation
import TskCore

public actor LocalTaskAttributeStore: TaskAttributeDefinitionsStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("attribute-definitions.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [TaskAttributeDefinition] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([TaskAttributeDefinition].self, from: Data(contentsOf: file))
    }

    public func save(_ definitions: [TaskAttributeDefinition]) throws {
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
