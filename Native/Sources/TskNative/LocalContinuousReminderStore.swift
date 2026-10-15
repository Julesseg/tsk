import CTaskChampion
import Foundation
import TskCore
#if canImport(UIKit)
import UIKit
#endif

public actor LocalContinuousReminderStore: ContinuousReminderConfigurationStore, ReminderImportCoordinating {
    private let directory: URL
    private let device: @Sendable () async throws -> UUID
    private var file: URL { directory.appendingPathComponent("continuous-reminders.json") }

    public init(directory: URL, deviceIdentifier: @escaping @Sendable () async throws -> UUID = LocalContinuousReminderStore.platformDeviceID) {
        self.directory = directory; device = deviceIdentifier
    }

    public func currentDeviceID() async throws -> UUID { try await device() }

    public func load() throws -> ContinuousReminderConfiguration? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(ContinuousReminderConfiguration.self, from: Data(contentsOf: file))
    }

    public func save(_ configuration: ContinuousReminderConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(configuration)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public func acquireImportLease() async throws -> any TaskMutationLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".tsk-reminder-import").path
        while true {
            try Task.checkCancellation()
            let descriptor = tsk_bridge_try_acquire_mutation(path)
            if descriptor >= 0 {
                let lease = NativeMutationLease(descriptor: descriptor)
                do { try Task.checkCancellation(); return lease }
                catch { lease.release(); throw error }
            }
            guard descriptor == -POSIXErrorCode.EWOULDBLOCK.rawValue || descriptor == -POSIXErrorCode.EINTR.rawValue else {
                throw TaskManagementError.storage(NSError(domain: NSPOSIXErrorDomain, code: Int(-descriptor)).localizedDescription)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    public func importPaused() throws -> Bool {
        let marker = directory.appendingPathComponent("continuous-reminders-paused")
        do {
            guard try Data(contentsOf: marker) == Data("paused".utf8) else { throw TaskManagementError.storage("Continuous import pause state is unreadable. Moving remains stopped.") }
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return false }
    }

    public func setImportPaused(_ paused: Bool) throws {
        let marker = directory.appendingPathComponent("continuous-reminders-paused")
        if paused {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try Data("paused".utf8).write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try Data("paused".utf8).write(to: marker, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        } else {
            do { try FileManager.default.removeItem(at: marker) }
            catch let error as CocoaError where error.code == .fileNoSuchFile {}
        }
    }

    public nonisolated static func platformDeviceID() async throws -> UUID {
        #if canImport(UIKit)
        return try await MainActor.run {
            guard let identifier = UIDevice.current.identifierForVendor else { throw ContinuousReminderError.deviceUnavailable }
            return identifier
        }
        #else
        throw ContinuousReminderError.deviceUnavailable
        #endif
    }
}
