import Foundation

public struct ContinuousReminderConfiguration: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let designatedDeviceID: UUID?
    public let mappings: [ReminderListMapping]
    public init(enabled: Bool, designatedDeviceID: UUID?, mappings: [ReminderListMapping]) {
        self.enabled = enabled; self.designatedDeviceID = designatedDeviceID; self.mappings = mappings
    }
}

public protocol ContinuousReminderConfigurationStore: Sendable {
    func currentDeviceID() async throws -> UUID
    func load() async throws -> ContinuousReminderConfiguration?
    func save(_ configuration: ContinuousReminderConfiguration) async throws
}

public struct ContinuousReminderStatus: Sendable {
    public let configuration: ContinuousReminderConfiguration?
    public let active: Bool
    public let configuredOnAnotherDevice: Bool
    public let paused: Bool
}

public extension TaskManager {
    func continuousReminderStatus() async throws -> ContinuousReminderStatus {
        guard let reminderImportConfiguration else { throw ContinuousReminderError.configurationUnavailable }
        let configuration = try await reminderImportConfiguration.load()
        let paused = try await reminderImportAdmission.importPaused()
        guard let configuration, configuration.enabled else {
            return ContinuousReminderStatus(configuration: configuration, active: false, configuredOnAnotherDevice: false, paused: paused)
        }
        guard let designated = configuration.designatedDeviceID else { throw ContinuousReminderError.deviceUnavailable }
        let matching = try await reminderImportConfiguration.currentDeviceID() == designated
        return ContinuousReminderStatus(configuration: configuration, active: matching, configuredOnAnotherDevice: !matching, paused: paused)
    }

    func configureContinuousReminders(enabled: Bool, mappings: [ReminderListMapping]) async throws {
        guard let reminderImportConfiguration else { throw ContinuousReminderError.configurationUnavailable }
        if enabled {
            guard !mappings.isEmpty else { throw ReminderImportError.noLists }
            guard Set(mappings.map(\.listID)).count == mappings.count else { throw ReminderImportError.duplicateList }
        }
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let prior = try await reminderImportConfiguration.load()
        let designated = enabled ? try await reminderImportConfiguration.currentDeviceID() : prior?.designatedDeviceID
        try await reminderImportConfiguration.save(ContinuousReminderConfiguration(enabled: enabled, designatedDeviceID: designated, mappings: mappings))
        try await reminderImportAdmission.setImportPaused(false)
    }

    func runContinuousReminderImport(from source: any ReminderMoveSource, retry: Bool = false) async throws -> ReminderMoveResult? {
        let admission = try await reminderImportAdmission.acquireImportLease()
        defer { admission.release() }
        try Task.checkCancellation()
        let status = try await continuousReminderStatus()
        guard status.active, let configuration = status.configuration, retry || !status.paused else { return nil }
        try await reminderImportAdmission.setImportPaused(true)
        do {
            let result = try await performReminderMove(from: source, mappings: configuration.mappings, configuration: configuration)
            try await reminderImportAdmission.setImportPaused(result.stopped)
            return result
        } catch {
            try await reminderImportAdmission.setImportPaused(true)
            throw error
        }
    }
}
