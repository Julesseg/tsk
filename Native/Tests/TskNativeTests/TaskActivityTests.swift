import Foundation
import Testing
import TskCore
import TskNative

@Test func nativeActivityReopensAndPreservesValidOccurrenceMasksAndUnfamiliarAttributes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "description": "Template", "recur": "weekly", "due": "1792310400", "mask": "W-", "opaque": "parent"])
    let source = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Active occurrence", "parent": parent.id.uuidString.lowercased(), "imask": "0", "scheduled": "1792108800", "due": "1792396800", "wait": "1792310400", "opaque": "child"])
    let sibling = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Sibling", "parent": parent.id.uuidString.lowercased(), "imask": "1", "due": "1793001600"])
    let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 1792144800) })
    let started = try await manager.start(id: source.id)
    #expect(started.attributes["start"] == "1792144800")
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.task(id: source.id) == started)
    #expect(try await reopened.task(id: parent.id) == parent)
    #expect(try await reopened.tasks(filter: "+ACTIVE").map(\.id) == [source.id])
    let stopped = try await manager.stop(id: source.id)
    #expect(stopped.attributes["start"] == nil)
    for key in ["scheduled", "due", "wait", "parent", "imask", "opaque"] { #expect(stopped.attributes[key] == source.attributes[key]) }
    _ = try await manager.start(id: source.id)
    let completed = try await manager.complete(id: source.id)
    #expect(completed.attributes["start"] == nil)
    #expect(try await reopened.task(id: parent.id).attributes["mask"] == "+-")
    #expect(try await reopened.task(id: sibling.id) == sibling)
    #expect(try await reopened.tasks(filter: "+ACTIVE").isEmpty)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.start(id: source.id) }
}

@Test func actualNativeActivitySaveFailurePreservesThePreviouslySavedStateAndAllowsRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Activity failure", attributes: ["opaque": "keep", "due": "2000000000"]))
    func sqlite(_ statement: String) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, statement]
        let error = Pipe(); process.standardError = error
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
    }
    try sqlite("CREATE TRIGGER activity_failure BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'activity save failure fixture'); END;")
    await #expect(throws: (any Error).self) { try await manager.start(id: original.id) }
    #expect(try await manager.task(id: original.id) == original)
    try sqlite("DROP TRIGGER activity_failure;")
    let active = try await manager.start(id: original.id)
    try sqlite("CREATE TRIGGER activity_failure BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'activity save failure fixture'); END;")
    await #expect(throws: (any Error).self) { try await manager.stop(id: original.id) }
    #expect(try await manager.task(id: original.id) == active)
    try sqlite("DROP TRIGGER activity_failure;")
    #expect(try await manager.stop(id: original.id).isActive == false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func encryptedTaskwarriorActivityRoundTripRetainsDatesAndCompletionClearsStart() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let rawClient = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClient))
    let configuration = try SyncConfiguration(serverURL: #require(environment["TSK_SYNC_TEST_URL"]), clientID: clientID, encryptionSecret: #require(environment["TSK_SYNC_TEST_SECRET"]))
    let manager = TaskChampionSession.makeManager(directory: root.appendingPathComponent("native"), now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Encrypted activity", attributes: ["scheduled": "1792108800", "due": "1792396800", "wait": "1792310400", "opaque": "keep café e\u{301}"]))
    _ = try await manager.start(id: original.id)
    _ = try await manager.synchronize(using: configuration)
    let taskrc = root.appendingPathComponent("taskrc")
    let desktop = root.appendingPathComponent("desktop")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    journal.time=0
    uda.opaque.type=string
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    var proof: [[String: Any]] = []
    func task(_ arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: try #require(environment["TSK_TASKWARRIOR_BINARY"]))
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=off"] + arguments
        var isolated = environment; isolated["TASKRC"] = taskrc.path; isolated["TASKDATA"] = desktop.path; isolated["TZ"] = "UTC"
        process.environment = isolated
        let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        proof.append(["arguments": arguments, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: diagnostic, as: UTF8.self)])
        guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: diagnostic, as: UTF8.self)) }
        return data
    }
    defer { if let file = environment["TSK_ACTIVITY_PROOF_PATH"], let data = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: file)) } }
    let id = original.id.uuidString.lowercased()
    _ = try task(["sync"])
    let exported = try #require((JSONSerialization.jsonObject(with: task([id, "+ACTIVE", "export"])) as? [[String: Any]])?.first)
    #expect(exported["start"] as? String == "20261016T100000Z")
    #expect(exported["scheduled"] as? String == "20261016T000000Z")
    _ = try task([id, "stop"]); _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    #expect(try await manager.task(id: original.id).isActive == false)
    _ = try task([id, "start"]); _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    #expect(try await manager.task(id: original.id).isActive)
    _ = try await manager.stop(id: original.id)
    _ = try await manager.start(id: original.id)
    let completed = try await manager.complete(id: original.id)
    #expect(!completed.isActive)
    #expect(completed.attributes["scheduled"] == original.attributes["scheduled"])
    #expect(completed.attributes["due"] == original.attributes["due"])
    #expect(completed.attributes["wait"] == original.attributes["wait"])
    #expect(completed.attributes["opaque"]?.matchesBytes("keep café e\u{301}") == true)
    _ = try await manager.synchronize(using: configuration); _ = try task(["sync"])
    let final = try #require((JSONSerialization.jsonObject(with: task([id, "export"])) as? [[String: Any]])?.first)
    #expect(final["status"] as? String == "completed")
    #expect(final["start"] == nil)
    #expect((try JSONSerialization.jsonObject(with: task([id, "+ACTIVE", "export"])) as? [[String: Any]])?.isEmpty == true)
    #expect(try await manager.task(id: original.id).id == original.id)
}
