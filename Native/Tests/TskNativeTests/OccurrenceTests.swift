import Foundation
import Testing
import TskCore
import TskNative

@Suite(.serialized)
struct OccurrenceTests {
    @Test @MainActor func nativeOccurrenceCommitIsAtomicAndChecksByteExactSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replica = TaskChampionReplica(directory: directory)
        let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "mask": "--", "opaque": "e\u{301}"])
        let child = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "occurrence", "parent": parent.id.uuidString, "imask": "0", "opaque": "retain"])
        let manager = TaskManager(replica: replica)
        let original = try await manager.tasks()
        let originalOperations = try sqlite(directory, "SELECT COUNT(*) FROM operations;")
        try sqlite(directory, "CREATE TRIGGER fail_atomic BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'atomic rollback fixture'); END;")
        await #expect(throws: (any Error).self) { try await manager.complete(id: child.id) }
        #expect(try await manager.tasks() == original)
        #expect(try sqlite(directory, "SELECT COUNT(*) FROM operations;") == originalOperations)
        try sqlite(directory, "DROP TRIGGER fail_atomic;")
        var stale = parent.attributes
        stale["opaque"] = "é"
        await #expect(throws: (any Error).self) {
            try await replica.updateAtomically([TaskAtomicUpdate(id: parent.id, expected: stale, changes: ["mask": "++"])])
        }
        #expect(try await manager.tasks() == original)
        let saved = try await manager.complete(id: child.id)
        #expect(saved.status == "completed")
        let reopened = try await TaskChampionSession.open(directory: directory)
        #expect(try await reopened.task(id: parent.id).attributes["mask"] == "+-")
        #expect(try await reopened.task(id: child.id).attributes["opaque"] == "retain")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
    @MainActor func actualTaskwarriorCompletionAndSubsequentGenerationPreserveMasksAndUnknownFields() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawClient = try #require(env["TSK_SYNC_TEST_GENERATOR_21_CLIENT_ID"] ?? env["TSK_SYNC_TEST_CLIENT_ID"])
        let config = try SyncConfiguration(serverURL: #require(env["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(env["TSK_SYNC_TEST_SECRET"]))
        let manager = try await TaskChampionSession.open(directory: root.appendingPathComponent("app"))
        let parent = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Occurrence interop", attributes: ["opaque": "keep café e\u{301}"]), firstDue: Date(timeIntervalSince1970: 3913092000), recurrence: "weekly"))
        _ = try await manager.synchronize(using: config)
        let taskrc = root.appendingPathComponent("taskrc")
        try """
        data.location=\(root.appendingPathComponent("desktop").path)
        confirmation=no
        recurrence.confirmation=no
        news.version=3.5.0
        recurrence.limit=3
        uda.opaque.type=string
        sync.server.url=\(config.serverURL)
        sync.server.client_id=\(config.clientID.uuidString.lowercased())
        sync.encryption_secret=\(config.encryptionSecret)

        """.write(to: taskrc, atomically: true, encoding: .utf8)
        var proof: [[String: Any]] = []
        func task(_ arguments: [String], generate: Bool = false) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: try #require(env["TSK_TASKWARRIOR_BINARY"]))
            process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=\(generate ? "on" : "off")"] + arguments
            var isolated = env
            isolated["TASKRC"] = taskrc.path
            isolated["TASKDATA"] = root.appendingPathComponent("desktop").path
            isolated["TZ"] = "UTC"
            process.environment = isolated
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let error = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            proof.append(["arguments": arguments, "generate": generate, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: error, as: UTF8.self)])
            guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: error, as: UTF8.self)) }
            return data
        }
        defer {
            if let path = env["TSK_OCCURRENCE_PROOF_PATH"], let data = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
        }
        _ = try task(["sync"])
        _ = try task(["rc.report.list.filter=", "list"], generate: true)
        _ = try task(["sync"])
        _ = try await manager.synchronize(using: config)
        let generated = try await manager.tasks().filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parent.id }.sorted { ($0.attributes["imask"] ?? "") < ($1.attributes["imask"] ?? "") }
        #expect(generated.count == 3)
        let first = try #require(generated.first), second = try #require(generated.dropFirst().first)
        _ = try await manager.update(id: first.id, changes: ["description": "Edited occurrence only"])
        let completed = try await manager.complete(id: first.id)
        #expect(completed.attributes["opaque"]?.matchesBytes("keep café e\u{301}") == true)
        #expect(try await manager.task(id: second.id) == second)
        _ = try await manager.synchronize(using: config)
        _ = try task(["sync"])
        let exported = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
        #expect(exported.contains { $0["uuid"] as? String == first.id.uuidString.lowercased() && $0["status"] as? String == "completed" })
        _ = try task([second.id.uuidString.lowercased(), "done"])
        _ = try task(["sync"])
        _ = try await manager.synchronize(using: config)
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "++-")
        #expect(try await manager.task(id: second.id).status == "completed")
        _ = try task(["rc.recurrence.limit=4", "rc.report.list.filter=", "list"], generate: true)
        _ = try task(["sync"])
        _ = try await manager.synchronize(using: config)
        let after = try await manager.tasks().filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parent.id }
        #expect(after.count == 4)
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "++--")
        #expect(try await manager.task(id: first.id).attributes == completed.attributes)
        #expect(generated.allSatisfy { old in after.contains { $0.id == old.id } })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
    @MainActor func twoActualProcessesCompleteSiblingOccurrencesWithoutLosingMaskPositions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replica = TaskChampionReplica(directory: directory)
        let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "mask": "--", "opaque": "preserve"])
        let first = try await replica.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0"])
        let second = try await replica.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "1"])
        let release = directory.appendingPathComponent("release")
        var processes: [Process] = []
        defer { for process in processes where process.isRunning { process.terminate() } }
        for (index, child) in [first, second].enumerated() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"]))
            process.arguments = ["complete-occurrence", directory.path, child.id.uuidString, directory.appendingPathComponent("ready\(index)").path, release.path, directory.appendingPathComponent("result\(index)").path]
            try process.run()
            processes.append(process)
        }
        let deadline = Date().addingTimeInterval(15)
        while !(0...1).allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready\($0)").path) }) {
            guard Date() < deadline else { throw TaskManagementError.storage("Child process barrier timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try Data().write(to: release)
        while processes.contains(where: \.isRunning) {
            guard Date() < deadline else { throw TaskManagementError.storage("Child process completion timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        for index in 0...1 {
            let result = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("result\(index)"))) as? [String: String])
            #expect(result["saved"] != nil)
        }
        let manager = try await TaskChampionSession.open(directory: directory)
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "++")
        #expect(try await manager.task(id: first.id).status == "completed")
        #expect(try await manager.task(id: second.id).status == "completed")
    }

    @discardableResult @MainActor private func sqlite(_ directory: URL, _ sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, sql]
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw TaskManagementError.storage(result) }
        return result
    }
}
