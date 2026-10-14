import Foundation
import TskCore

public actor SyncConfigurationStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("sync-configuration.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> SyncConfiguration? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SyncConfiguration.self, from: Data(contentsOf: file))
    }

    public func save(_ configuration: SyncConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(configuration)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
