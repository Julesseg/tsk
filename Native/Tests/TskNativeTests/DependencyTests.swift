import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func dependencyLinksPersistAndTaskwarriorBlockingAgreesAfterPrerequisiteCompletion() async throws {
    let fixture = try DependencyNativeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let reference = Date()
    let manager = TaskManager(replica: TaskChampionReplica(directory: fixture.data), now: { reference })
    let prerequisite = try await manager.create(TaskDraft(description: "Prerequisite outside Today", attributes: ["project": "Other"]))
    let dependent = try await manager.create(TaskDraft(description: "Dependent planned task", attributes: ["scheduled": "1791928800", "due": "1792015200", "wait": String(Int(reference.timeIntervalSince1970) + 3600), "opaque": "retain exactly", "project": "Selected"]))
    _ = try await manager.addDependency(id: dependent.id, prerequisiteID: prerequisite.id)
    let reopened = TaskManager(replica: TaskChampionReplica(directory: fixture.data), now: { reference })
    let availability = try await reopened.availability(id: dependent.id)
    #expect(availability.isWaiting)
    #expect(availability.isBlocked)
    #expect(try await reopened.tasks(query: .today, project: .project("Selected")).map(\.id) == [dependent.id])
    #expect(try fixture.export([dependent.id.uuidString.lowercased(), "+BLOCKED"]).count == 1)
    #expect(try fixture.export([prerequisite.id.uuidString.lowercased(), "+BLOCKING"]).count == 1)
    _ = try await reopened.complete(id: prerequisite.id)
    #expect(!(try await reopened.availability(id: dependent.id).isBlocked))
    #expect(try await reopened.availability(id: dependent.id).isWaiting)
    #expect(try fixture.export([dependent.id.uuidString.lowercased(), "+BLOCKED"]).isEmpty)
    let completedTarget = try #require(try fixture.export([dependent.id.uuidString.lowercased()]).first)
    #expect(completedTarget["depends"] as? [String] == [prerequisite.id.uuidString.lowercased()])
    #expect(completedTarget["opaque"] as? String == "retain exactly")
    let stored = try await reopened.task(id: dependent.id)
    #expect(stored.attributes["scheduled"] == "1791928800")
    #expect(stored.attributes["due"] == "1792015200")
    #expect(stored.attributes["dep_\(prerequisite.id.uuidString.lowercased())"] == "x")
    _ = try await reopened.removeDependency(id: dependent.id, reference: prerequisite.id.uuidString.lowercased())
    let final = TaskManager(replica: TaskChampionReplica(directory: fixture.data), now: { reference })
    #expect(try await final.task(id: dependent.id).dependencyReferences.isEmpty)
    #expect(try await final.task(id: dependent.id).attributes["depends"] == nil)
    let exported = try #require(try fixture.export([dependent.id.uuidString.lowercased()]).first)
    #expect(exported["depends"] == nil)
    #expect((exported["uuid"] as? String)?.lowercased() == dependent.id.uuidString.lowercased())
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func nativeMissingUppercaseAndMalformedDependenciesRemainDiagnosedUnblockedAndRepairable() async throws {
    let fixture = try DependencyNativeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let replica = TaskChampionReplica(directory: fixture.data)
    let target = try await replica.create(id: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!, attributes: ["description": "Target", "status": "pending"])
    let missing = "aaaaaaaa-0000-4000-8000-000000000004"
    let owner = try await replica.create(id: UUID(), attributes: ["description": "Diagnostics owner", "status": "pending", "dep_\(target.id.uuidString)": "uppercase opaque", "dep_\(missing)": "missing opaque", "dep_bad reference": "invalid opaque", "opaque": "retain"])
    let manager = TaskManager(replica: replica)
    let availability = try await manager.availability(id: owner.id)
    #expect(!availability.isBlocked)
    #expect(availability.diagnostics.count == 3)
    #expect(try fixture.export([owner.id.uuidString.lowercased(), "+BLOCKED"]).isEmpty)
    #expect(try fixture.export([owner.id.uuidString.lowercased(), "+UNBLOCKED"]).count == 1)
    _ = try await manager.update(id: owner.id, changes: ["description": "Unrelated edit"])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: fixture.data))
    #expect(try await reopened.task(id: owner.id).attributes["dep_\(target.id.uuidString)"] == "uppercase opaque")
    #expect(try await reopened.task(id: owner.id).attributes["dep_bad reference"] == "invalid opaque")
    _ = try await reopened.removeDependency(id: owner.id, reference: "bad reference")
    #expect(try await reopened.task(id: owner.id).attributes["dep_bad reference"] == nil)
    #expect(try await reopened.task(id: owner.id).attributes["dep_\(missing)"] == "missing opaque")
    #expect(try await reopened.task(id: owner.id).attributes["opaque"] == "retain")
}

private struct DependencyNativeFixture {
    let directory: URL
    let data: URL
    let config: URL
    let binary: String

    init() throws {
        binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        data = directory.appendingPathComponent("data")
        config = directory.appendingPathComponent("taskrc")
        try "data.location=\(data.path)\nuda.opaque.type=string\nconfirmation=no\ndependency.confirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    }

    func export(_ filter: [String]) throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + filter + ["export"]
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = data.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func dependencyAddAndRemoveAutomaticallySyncAndDesktopCompletionRecomputesBlocking() async throws {
    let environment = ProcessInfo.processInfo.environment
    let fixture = try DependencyNativeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let serverURL = try #require(environment["TSK_SYNC_TEST_URL"])
    let rawClient = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let configuration = try SyncConfiguration(serverURL: serverURL, clientID: client, encryptionSecret: secret)
    let nativeDirectory = fixture.directory.appendingPathComponent("native")
    let manager = TaskManager(replica: TaskChampionReplica(directory: nativeDirectory))
    let prerequisite = try await manager.create(TaskDraft(description: "Desktop completes prerequisite"))
    let dependent = try await manager.create(TaskDraft(description: "Synced dependent", attributes: ["opaque": "sync retain", "scheduled": "1791928800"]))
    _ = try await manager.synchronize(using: configuration)
    let syncSettings = "sync.server.url=\(configuration.serverURL)\nsync.server.client_id=\(configuration.clientID.uuidString.lowercased())\nsync.encryption_secret=\(configuration.encryptionSecret)\n"
    let writer = try FileHandle(forWritingTo: fixture.config)
    try writer.seekToEnd()
    try writer.write(contentsOf: Data(syncSettings.utf8))
    try writer.close()
    _ = try await manager.addDependency(id: dependent.id, prerequisiteID: prerequisite.id)
    try await awaitDependencySynchronization(manager)
    try fixture.command(["sync"])
    let linked = try #require(try fixture.export([dependent.id.uuidString.lowercased()]).first)
    #expect(linked["depends"] as? [String] == [prerequisite.id.uuidString.lowercased()])
    #expect(linked["opaque"] as? String == "sync retain")
    try fixture.command([prerequisite.id.uuidString.lowercased(), "done"])
    try fixture.command(["sync"])
    _ = try await manager.synchronize(trigger: .manualRetry)
    #expect(!(try await manager.availability(id: dependent.id).isBlocked))
    #expect(try await manager.task(id: dependent.id).dependencyReferences == [prerequisite.id.uuidString.lowercased()])
    _ = try await manager.removeDependency(id: dependent.id, reference: prerequisite.id.uuidString.lowercased())
    try await awaitDependencySynchronization(manager)
    try fixture.command(["sync"])
    let cleared = try #require(try fixture.export([dependent.id.uuidString.lowercased()]).first)
    #expect(cleared["depends"] == nil)
    #expect(cleared["opaque"] as? String == "sync retain")
    #expect((cleared["uuid"] as? String)?.lowercased() == dependent.id.uuidString.lowercased())
    await manager.suspendSynchronization()
}

private func awaitDependencySynchronization(_ manager: TaskManager) async throws {
    for await state in await manager.synchronizationUpdates() {
        if case .synchronized = state { return }
        if case .failed(let message) = state { throw SynchronizationError.failed(message) }
    }
    throw SynchronizationError.failed("Synchronization ended without completing the dependency change.")
}

private extension DependencyNativeFixture {
    func command(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = data.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
