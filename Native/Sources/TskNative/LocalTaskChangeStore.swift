import CTaskChampion
import Foundation
import TskCore
#if os(iOS) && canImport(WidgetKit)
import WidgetKit
#endif

public actor LocalTaskChangeStore: TaskChangeTracking {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func current() throws -> TaskChangeVersion { try Self.read(directory) }

    public func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) async throws {
        try await Task.detached { [directory] in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = tsk_bridge_acquire_mutation(directory.appendingPathComponent(".tsk-change-versions").path)
            guard descriptor >= 0 else { throw TaskManagementError.storage(NSError(domain: NSPOSIXErrorDomain, code: Int(-descriptor)).localizedDescription) }
            let lease = NativeMutationLease(descriptor: descriptor)
            defer { lease.release() }
            var version = try Self.read(directory)
            version.advance(domain, origin: origin)
            let data = try JSONEncoder().encode(version)
            let file = directory.appendingPathComponent("participant-changes.json")
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }.value
        #if os(iOS) && canImport(WidgetKit)
        if #available(iOS 14, macOS 11, *) { WidgetCenter.shared.reloadTimelines(ofKind: "tsk.tasks") }
        #endif
    }

    private static func read(_ directory: URL) throws -> TaskChangeVersion {
        let file = directory.appendingPathComponent("participant-changes.json")
        do { return try JSONDecoder().decode(TaskChangeVersion.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .initial }
    }
}
