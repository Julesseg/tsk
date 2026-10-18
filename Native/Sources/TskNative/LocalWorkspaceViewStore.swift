import Foundation
import TskCore

public struct LocalWorkspaceViewStore: Sendable {
    private let file: URL

    public init(directory: URL) {
        file = directory.appendingPathComponent("workspace-views.json")
    }

    public func load(customIDs: [UUID]) throws -> WorkspaceViews {
        guard FileManager.default.fileExists(atPath: file.path) else { return WorkspaceViews(customIDs: customIDs) }
        var views = try JSONDecoder().decode(WorkspaceViews.self, from: Data(contentsOf: file))
        views.reconcile(customIDs: customIDs)
        return views
    }

    public func save(_ views: WorkspaceViews) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(views)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
