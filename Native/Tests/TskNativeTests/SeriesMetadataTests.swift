import Foundation
import Testing
import TskCore
import TskNative

@Suite(.serialized)
struct SeriesMetadataTests {
    @Test func nativeSeriesSnapshotGuardRejectsPhantomsAndOverdueTasksMovedIntoTheFuture() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replica = TaskChampionReplica(directory: directory)
        let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "mask": "--", "description": "Series"])
        let past = try await replica.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0", "due": "50"])
        let snapshot = try await replica.tasks()
        let updates = [TaskAtomicUpdate(id: parent.id, expected: parent.attributes, changes: ["description": "Changed"])]
        let phantom = try await replica.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "1", "due": "200"])
        await #expect(throws: (any Error).self) { try await replica.updateAtomically(updates, expecting: snapshot) }
        #expect(try await replica.tasks().first(where: { $0.id == parent.id }) == parent)
        let refreshed = try await replica.tasks()
        _ = try await replica.updateAtomically([TaskAtomicUpdate(id: past.id, expected: past.attributes, changes: ["due": "300"])])
        await #expect(throws: (any Error).self) { try await replica.updateAtomically(updates, expecting: refreshed) }
        let stable = try await replica.tasks()
        let result = try await replica.updateAtomically(updates, expecting: stable)
        #expect(result.first?.description == "Changed")
        #expect(try await replica.tasks().first(where: { $0.id == phantom.id }) == phantom)
    }
    @Test func publicSeriesSaveRejectsActualNativeWritesAfterCoreRevalidation() async throws {
        for insertsChild in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let native = TaskChampionReplica(directory: directory)
            let parent = try await native.create(id: UUID(), attributes: ["status": "recurring", "description": "Original", "mask": "--"])
            let overdue = try await native.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0", "due": "50"])
            let race = SeriesRaceReplica(native: native, parent: parent.id, overdue: overdue, insertsChild: insertsChild)
            let manager = TaskManager(replica: race, now: { Date(timeIntervalSince1970: 100) })
            let preview = try await manager.previewSeriesMetadata(id: parent.id, changes: ["description": "Revised"])
            #expect(preview.affected.isEmpty)
            await #expect(throws: (any Error).self) { try await manager.applySeriesMetadata(preview) }
            #expect(try await manager.task(id: parent.id) == parent)
            let current = try await manager.tasks()
            if insertsChild { #expect(current.contains { $0.attributes["imask"] == "1" && $0.attributes["due"] == "200" }) }
            else { #expect(current.first { $0.id == overdue.id }?.attributes["due"] == "300") }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
    @MainActor func seriesMetadataPropagatesThroughRealTaskwarriorAndContinuedGenerationWithoutRewritingHistory() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawClient = try #require(env["TSK_SYNC_TEST_GENERATOR_22_CLIENT_ID"] ?? env["TSK_SYNC_TEST_CLIENT_ID"])
        let config = try SyncConfiguration(serverURL: #require(env["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(env["TSK_SYNC_TEST_SECRET"]))
        let manager = try await TaskChampionSession.open(directory: root.appendingPathComponent("app"))
        _ = try await manager.saveAttributeDefinition(name: "effort", type: .duration)
        let parent = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Occurrence interop", attributes: ["opaque": "keep café e\u{301}", "tag_old": "", "annotation_1792000000": "original note", "effort": "2h"]), firstDue: Date(timeIntervalSince1970: 3913092000), recurrence: "weekly"))
        _ = try await manager.synchronize(using: config)
        let taskrc = root.appendingPathComponent("taskrc")
        try """
        data.location=\(root.appendingPathComponent("desktop").path)
        confirmation=no
        recurrence.confirmation=no
        news.version=3.5.0
        recurrence.limit=3
        uda.opaque.type=string
        uda.effort.type=duration
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
            if let path = env["TSK_SERIES_METADATA_PROOF_PATH"], let data = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
        }
        _ = try task(["sync"])
        _ = try task(["rc.report.list.filter=", "list"], generate: true)
        _ = try task(["sync"])
        _ = try await manager.synchronize(using: config)
        let generated = try await manager.tasks().filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parent.id }.sorted { ($0.attributes["imask"] ?? "") < ($1.attributes["imask"] ?? "") }
        #expect(generated.count == 3)
        let first = try #require(generated.first), second = try #require(generated.dropFirst().first)
        let completed = try await manager.complete(id: first.id)
        _ = try await manager.update(id: second.id, changes: ["opaque": "occurrence opaque", "tag_personal": ""])
        _ = try await manager.addAnnotation(id: second.id, text: "Occurrence-only note")
        let beforeParent = try await manager.task(id: parent.id)
        let preview = try await manager.previewSeriesMetadata(id: parent.id, changes: ["description": "Updated series", "project": "Work.Review", "priority": "H", "tag_old": nil, "tag_new": "", "annotation_1792000000": "edited series note", "effort": "45min"], addingAnnotation: "Added series note")
        #expect(preview.affected.count == 2)
        #expect(try await manager.task(id: parent.id) == beforeParent)
        _ = try await manager.applySeriesMetadata(preview)
        let updated = try await manager.task(id: second.id)
        #expect(updated.description == "Updated series")
        #expect(updated.tags == ["new", "personal"])
        #expect(updated.attributes["opaque"] == "occurrence opaque")
        #expect(updated.attributes["effort"] == "PT45M")
        #expect(updated.annotations.contains { $0.text == "Occurrence-only note" })
        #expect(updated.annotations.contains { $0.text == "Added series note" })
        #expect(try await manager.task(id: first.id) == completed)
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "+--")
        #expect(try await manager.task(id: parent.id).attributes["due"] == beforeParent.attributes["due"])
        _ = try await manager.synchronize(using: config)
        _ = try task(["sync"])
        let exported = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
        let external = try #require(exported.first { $0["uuid"] as? String == second.id.uuidString.lowercased() })
        #expect(external["description"] as? String == "Updated series")
        #expect(external["project"] as? String == "Work.Review")
        #expect(external["priority"] as? String == "H")
        #expect(external["effort"] as? String == "PT45M")
        #expect((external["annotations"] as? [[String: Any]])?.contains { $0["description"] as? String == "edited series note" } == true)
        _ = try task(["rc.recurrence.limit=4", "rc.report.list.filter=", "list"], generate: true)
        _ = try task(["sync"])
        _ = try await manager.synchronize(using: config)
        let after = try await manager.tasks().filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parent.id }
        #expect(after.count == 4)
        let next = try #require(after.first { $0.attributes["imask"] == "3" })
        #expect(next.description == "Updated series")
        #expect(next.project == "Work.Review")
        #expect(next.priority == "H")
        #expect(next.tags == ["new"])
        #expect(next.attributes["effort"] == "PT45M")
        #expect(next.attributes["opaque"]?.matchesBytes("keep café e\u{301}") == true)
        #expect(next.annotations.contains { $0.text == "Added series note" })
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "+---")
        #expect(try await manager.task(id: first.id).attributes == completed.attributes)
        #expect(generated.allSatisfy { old in after.contains { $0.id == old.id } })
    }

}

private actor SeriesRaceReplica: TaskAtomicSnapshotMutatingReplica, TaskMutationCoordinatingReplica {
    let native: TaskChampionReplica
    let parent: UUID
    let overdue: TaskRecord
    let insertsChild: Bool
    init(native: TaskChampionReplica, parent: UUID, overdue: TaskRecord, insertsChild: Bool) {
        self.native = native; self.parent = parent; self.overdue = overdue; self.insertsChild = insertsChild
    }
    func tasks() async throws -> [TaskRecord] { try await native.tasks() }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { try await native.create(id: id, attributes: attributes) }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { try await native.update(id: id, changes: changes) }
    func acquireMutationLease() async throws -> any TaskMutationLease { try await native.acquireMutationLease() }
    func updateAtomically(_ updates: [TaskAtomicUpdate]) async throws -> [TaskRecord] { try await native.updateAtomically(updates) }
    func updateAtomically(_ updates: [TaskAtomicUpdate], expecting records: [TaskRecord]) async throws -> [TaskRecord] {
        if insertsChild { _ = try await native.create(id: UUID(), attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1", "due": "200"]) }
        else { _ = try await native.updateAtomically([TaskAtomicUpdate(id: overdue.id, expected: overdue.attributes, changes: ["due": "300"])]) }
        return try await native.updateAtomically(updates, expecting: records)
    }
}
