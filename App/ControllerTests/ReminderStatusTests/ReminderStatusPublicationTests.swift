import Foundation
import Observation
import Testing
import TskCore

@MainActor final class TaskStore {
    let manager: TaskManager
    init(manager: TaskManager) { self.manager = manager }
    func reload() async {}
}

@MainActor enum SynchronizationAppDelegate {
    static func scheduleRefresh() {}
}

private actor ReminderStatusSettings: ContinuousReminderConfigurationStore {
    let device: UUID
    var configuration: ContinuousReminderConfiguration?
    var reads = 0
    var failing = false

    init(device: UUID, configuration: ContinuousReminderConfiguration?) {
        self.device = device
        self.configuration = configuration
    }

    func currentDeviceID() -> UUID { device }
    func load() throws -> ContinuousReminderConfiguration? {
        reads += 1
        if failing { throw TaskManagementError.storage("Status unavailable") }
        return configuration
    }
    func save(_ configuration: ContinuousReminderConfiguration) { self.configuration = configuration }
    func remove() { configuration = nil }
    func fail() { failing = true }
}

private struct ReminderStatusReplica: TaskReplica {
    func tasks() -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord { throw TaskManagementError.storage("Unexpected task creation") }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.storage("Unexpected task update") }
}

@Test @MainActor func reminderControllerPublishesTheFirstStatusRead() async {
    let settings = ReminderStatusSettings(device: UUID(), configuration: nil)
    let manager = TaskManager(replica: ReminderStatusReplica(), reminderImportConfiguration: settings)
    let controller = ContinuousReminderController(store: TaskStore(manager: manager))
    #expect(controller.status == nil)
    await confirmation(expectedCount: 1) { notification in
        withObservationTracking { _ = controller.status } onChange: { notification() }
        await controller.load()
    }
    #expect(controller.status?.active == false)
    #expect(await settings.reads == 1)
}

@Test @MainActor func reminderControllerReadsEveryTimeAndPublishesOnlyCompleteStatusChanges() async {
    let device = UUID()
    let mappings = [ReminderListMapping(listID: "work", project: "Office"), ReminderListMapping(listID: "home", project: "House")]
    let original = ContinuousReminderConfiguration(enabled: true, designatedDeviceID: device, mappings: mappings)
    let cases: [(String, ContinuousReminderConfiguration?, Bool, Int)] = [
        ("identical", original, false, 0),
        ("configuration removed", nil, false, 1),
        ("disabled", ContinuousReminderConfiguration(enabled: false, designatedDeviceID: device, mappings: mappings), false, 1),
        ("other device", ContinuousReminderConfiguration(enabled: true, designatedDeviceID: UUID(), mappings: mappings), false, 1),
        ("mapping order", ContinuousReminderConfiguration(enabled: true, designatedDeviceID: device, mappings: Array(mappings.reversed())), false, 1),
        ("mapped project", ContinuousReminderConfiguration(enabled: true, designatedDeviceID: device, mappings: [ReminderListMapping(listID: "work", project: "Release"), mappings[1]]), false, 1),
        ("source list", ContinuousReminderConfiguration(enabled: true, designatedDeviceID: device, mappings: [ReminderListMapping(listID: "other", project: "Office"), mappings[1]]), false, 1),
        ("paused", original, true, 1)
    ]
    for (name, configuration, paused, count) in cases {
        let settings = ReminderStatusSettings(device: device, configuration: original)
        let admission = ReminderImportCoordinator()
        let manager = TaskManager(replica: ReminderStatusReplica(), reminderImportConfiguration: settings, reminderImportAdmission: admission)
        let controller = ContinuousReminderController(store: TaskStore(manager: manager))
        await controller.load()
        if let configuration { await settings.save(configuration) }
        else { await settings.remove() }
        admission.setImportPaused(paused)
        await confirmation("Status read: \(name)", expectedCount: count) { notification in
            withObservationTracking { _ = controller.status } onChange: { notification() }
            await controller.load()
        }
        #expect(controller.status?.configuration == configuration)
        #expect(controller.status?.paused == paused)
        #expect(controller.status?.active == (configuration?.enabled == true && configuration?.designatedDeviceID == device))
        #expect(controller.status?.configuredOnAnotherDevice == (configuration?.enabled == true && configuration?.designatedDeviceID != device))
        #expect(await settings.reads == 2)
    }
}

@Test @MainActor func reminderControllerReportsReadErrorsWithoutReplacingStatus() async {
    let settings = ReminderStatusSettings(device: UUID(), configuration: nil)
    let manager = TaskManager(replica: ReminderStatusReplica(), reminderImportConfiguration: settings)
    let controller = ContinuousReminderController(store: TaskStore(manager: manager))
    await controller.load()
    let prior = controller.status
    await settings.fail()
    await confirmation(expectedCount: 0) { notification in
        withObservationTracking { _ = controller.status } onChange: { notification() }
        await controller.load()
    }
    #expect(controller.status?.configuration == prior?.configuration)
    #expect(controller.status?.active == prior?.active)
    #expect(controller.status?.configuredOnAnotherDevice == prior?.configuredOnAnotherDevice)
    #expect(controller.status?.paused == prior?.paused)
    #expect(controller.error?.contains("Status unavailable") == true)
    #expect(await settings.reads == 2)
}
