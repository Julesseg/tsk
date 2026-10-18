import Foundation
import Testing
import TskCore
import TskNative

@Test func serverConfigurationSurvivesRelaunchWithoutEnteringTaskAttributes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SyncConfigurationStore(directory: directory)
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated secret with spaces")
    try await store.save(configuration)
    #expect(try await SyncConfigurationStore(directory: directory).load() == configuration)
    try await store.remove()
    #expect(try await store.load() == nil)
}

@Test func failedNativeSynchronizationPreservesLocallyCommittedTask() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let saved = try await manager.create(TaskDraft(description: "Offline task survives sync failure", attributes: ["opaque": "exactly preserved"]))
    let unavailable = try SyncConfiguration(serverURL: "http://127.0.0.1:1", clientID: UUID(), encryptionSecret: "isolated-secret")
    do {
        _ = try await manager.synchronize(using: unavailable)
        Issue.record("Unavailable server must fail synchronization")
    } catch let failure as SynchronizationError {
        if case .failed(let message) = failure {
            #expect(message.contains("Failed to synchronize with server"))
        } else { Issue.record("Expected an actual server failure, received \(failure)") }
    }
    #expect(try await manager.task(id: saved.id) == saved)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func realEncryptedTaskwarriorSyncConvergesBothWaysAndRetainsOpaqueFields() async throws {
    let environment = ProcessInfo.processInfo.environment
    let binary = try #require(environment["TSK_TASKWARRIOR_BINARY"])
    let rawClientID = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClientID))
    let configuration = try SyncConfiguration(serverURL: try #require(environment["TSK_SYNC_TEST_URL"]), clientID: clientID, encryptionSecret: try #require(environment["TSK_SYNC_TEST_SECRET"]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("native")))
    let native = try await manager.create(TaskDraft(description: "Phone to desktop", attributes: ["customOpaque": "phone original", "annotation_1792015200": "Retain native annotation"]))
    _ = try await manager.synchronize(using: configuration)
    let desktop = directory.appendingPathComponent("desktop")
    let taskrc = directory.appendingPathComponent("taskrc")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    uda.customOpaque.type=string
    uda.customOpaque.label=Opaque
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    func task(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=off"] + arguments
        var executionEnvironment = environment
        executionEnvironment["TASKRC"] = taskrc.path
        executionEnvironment["TASKDATA"] = desktop.path
        process.environment = executionEnvironment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SynchronizationError.failed(String(decoding: error, as: UTF8.self))
        }
        return data
    }
    #expect(String(decoding: try task(["_version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    _ = try task(["sync"])
    let exported = try #require(JSONSerialization.jsonObject(with: task([native.id.uuidString.lowercased(), "export"])) as? [[String: Any]])
    let onDesktop = try #require(exported.first)
    #expect(onDesktop["uuid"] as? String == native.id.uuidString.lowercased())
    #expect(onDesktop["description"] as? String == "Phone to desktop")
    #expect(onDesktop["customOpaque"] as? String == "phone original")
    _ = try task([native.id.uuidString.lowercased(), "modify", "description:Desktop edit", "customOpaque:desktop opaque"])
    let remoteDescription = "Desktop to phone \(UUID().uuidString)"
    _ = try task(["add", remoteDescription, "project:Interop"])
    let added = try #require(JSONSerialization.jsonObject(with: task(["description.is:\(remoteDescription)", "export"])) as? [[String: Any]])
    let rawDesktopID = try #require(added.first?["uuid"] as? String)
    let desktopID = try #require(UUID(uuidString: rawDesktopID))
    _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    let updated = try await manager.task(id: native.id)
    #expect(updated.description == "Desktop edit")
    #expect(updated.attributes["customOpaque"] == "desktop opaque")
    #expect(updated.attributes["annotation_1792015200"] == "Retain native annotation")
    #expect(try await manager.task(id: desktopID).description == remoteDescription)
    #expect(try await manager.task(id: desktopID).attributes["project"] == "Interop")
    let final = try await manager.synchronize(using: configuration)
    #expect(final.filter { $0.id == native.id }.count == 1)
    #expect(final.filter { $0.id == desktopID }.count == 1)
    let wrongSecret = try SyncConfiguration(serverURL: configuration.serverURL, clientID: configuration.clientID, encryptionSecret: "wrong isolated secret")
    let other = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("wrong-secret")))
    let retained = try await other.create(TaskDraft(description: "Wrong credentials still preserve offline capture"))
    await #expect(throws: (any Error).self) { try await other.synchronize(using: wrongSecret) }
    #expect(try await other.task(id: retained.id) == retained)
}
