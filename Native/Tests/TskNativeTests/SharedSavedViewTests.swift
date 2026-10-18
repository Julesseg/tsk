import Foundation
import Testing
import TskCore
import TskNative

@Test func nativeFactoriesReopenTheSameDeviceLocalSavedViews() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try await TaskChampionSession.open(directory: directory)
    let saved = try await first.saveView(name: "Shared work", expression: "project:Work")
    let second = try await TaskChampionSession.open(directory: directory)
    #expect(try await second.savedViews() == [saved])
    try await second.deleteView(id: saved.id)
    #expect(try await first.savedViews().isEmpty)
}

@Test func concurrentSavedViewsRetainBothDefinitionsAcrossReentrantAndIndependentManagers() async throws {
    for independent in [false, true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("replica")
        let release = directory.appendingPathComponent("release")
        let firstReady = directory.appendingPathComponent("first-ready")
        let secondReady = directory.appendingPathComponent("second-ready")
        let firstStore = HeldViewStore(directory: storage, markers: independent ? [firstReady] : [firstReady, secondReady], release: release)
        let firstManager = TaskManager(replica: TaskChampionReplica(directory: storage), viewDefinitions: firstStore)
        let secondManager = independent ? TaskManager(replica: TaskChampionReplica(directory: storage), viewDefinitions: HeldViewStore(directory: storage, markers: [secondReady], release: release)) : firstManager
        let first = Task { try await firstManager.saveView(name: "First", expression: "project:First") }
        try await waitForViewFile(firstReady)
        let second = Task { try await secondManager.saveView(name: "Second", expression: "project:Second") }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: secondReady.path), "Another writer must wait before loading its definition snapshot")
        try Data().write(to: release)
        let saved = try await [first.value, second.value]
        let reopened = try await TaskChampionSession.open(directory: storage)
        #expect(Set(try await reopened.savedViews().map(\.id)) == Set(saved.map(\.id)))
    }
}

private actor HeldViewStore: TaskViewDefinitionsStore {
    let native: LocalTaskViewStore
    let markers: [URL]
    let release: URL
    var reads = 0

    init(directory: URL, markers: [URL], release: URL) {
        native = LocalTaskViewStore(directory: directory)
        self.markers = markers
        self.release = release
    }

    func load() async throws -> [SavedTaskView] {
        let definitions = try await native.load()
        let index = reads
        reads += 1
        if index < markers.count {
            try Data().write(to: markers[index])
            try await waitForViewFile(release)
        }
        return definitions
    }

    func save(_ definitions: [SavedTaskView]) async throws { try await native.save(definitions) }
}

private func waitForViewFile(_ file: URL) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !FileManager.default.fileExists(atPath: file.path) {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Saved-view fixture timed out") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
@MainActor func separateProcessesSaveDistinctViewsWithoutReplacingAnotherSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("replica")
    let release = directory.appendingPathComponent("release")
    let firstReady = directory.appendingPathComponent("first-ready")
    let secondReady = directory.appendingPathComponent("second-ready")
    let firstOutput = directory.appendingPathComponent("first-output")
    let secondOutput = directory.appendingPathComponent("second-output")
    func launch(_ name: String, ready: URL, output: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"]))
        process.arguments = ["save-view", storage.path, name, ready.path, release.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
    let first = try launch("First", ready: firstReady, output: firstOutput)
    let second = try launch("Second", ready: secondReady, output: secondOutput)
    defer {
        try? Data().write(to: release)
        for process in [first, second] { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !FileManager.default.fileExists(atPath: firstReady.path) && !FileManager.default.fileExists(atPath: secondReady.path) {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("No saved-view process reached its read") }
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(200))
    #expect(FileManager.default.fileExists(atPath: firstReady.path) != FileManager.default.fileExists(atPath: secondReady.path))
    try Data().write(to: release)
    try await waitForViewFile(firstOutput)
    try await waitForViewFile(secondOutput)
    while first.isRunning || second.isRunning {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Saved-view process did not exit") }
        try await Task.sleep(for: .milliseconds(10))
    }
    let outputs = try [firstOutput, secondOutput].map { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: String]) }
    #expect(outputs.allSatisfy { $0["saved"] != nil })
    let reopened = try await TaskChampionSession.open(directory: storage)
    #expect(Set(try await reopened.savedViews().map(\.name)) == ["First", "Second"])
}

@Test func viewOnlyChangesDoNotRequestTaskSynchronization() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let configuration = try SyncConfiguration(serverURL: "http://127.0.0.1:1", clientID: UUID(), encryptionSecret: "isolated-view-only-fixture")
    await manager.configureSynchronization(configuration)
    let saved = try await manager.saveView(name: "Local", expression: "project:Work")
    #expect(await manager.synchronizationStatus() == .ready)
    try await manager.deleteView(id: saved.id)
    #expect(await manager.synchronizationStatus() == .ready)
    #expect(try await manager.tasks().isEmpty)
}

@Test func concurrentViewDeletionAndCreationPreserveUnrelatedDefinitions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let baseline = try await TaskChampionSession.open(directory: directory)
    let removed = try await baseline.saveView(name: "Remove", expression: "project:Remove")
    let kept = try await baseline.saveView(name: "Keep", expression: "project:Keep")
    let ready = directory.appendingPathComponent("ready")
    let release = directory.appendingPathComponent("release")
    defer { try? Data().write(to: release) }
    let deleting = TaskManager(replica: TaskChampionReplica(directory: directory), viewDefinitions: HeldViewStore(directory: directory, markers: [ready], release: release))
    let first = Task { try await deleting.deleteView(id: removed.id) }
    try await waitForViewFile(ready)
    let adding = try await TaskChampionSession.open(directory: directory)
    let second = Task { try await adding.saveView(name: "New", expression: "project:New") }
    try await Task.sleep(for: .milliseconds(200))
    try Data().write(to: release)
    try await first.value
    let added = try await second.value
    #expect(Set(try await baseline.savedViews().map(\.id)) == [kept.id, added.id])
}
