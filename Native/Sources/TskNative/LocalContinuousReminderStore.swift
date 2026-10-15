import Foundation
import TskCore
#if canImport(UIKit)
import UIKit
#endif

public actor LocalContinuousReminderStore: ContinuousReminderConfigurationStore {
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
