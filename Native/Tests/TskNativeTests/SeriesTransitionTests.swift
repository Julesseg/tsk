import Foundation
import Testing
import TskCore
import TskNative

@Suite(.serialized)
struct SeriesTransitionTests {
    @Test @MainActor func nativeTransitionCreatesAndUpdatesInOneRollbackSafeTransaction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replica = TaskChampionReplica(directory: directory)
        let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "description": "Original", "due": "4000", "recur": "weekly", "mask": "-", "opaque": "preserve"])
        let child = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Child", "parent": parent.id.uuidString, "imask": "0", "due": "4000", "opaque": "child"])
        let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) })
        let preview = try await manager.previewSeriesTransition(id: parent.id, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 2000), firstDue: Date(timeIntervalSince1970: 4000100000), recurrence: "monthly", generatorTimeZone: "UTC"))
        let before = try await manager.tasks()
        let operations = try sql(directory, "SELECT COUNT(*) FROM operations;")
        try sql(directory, "CREATE TRIGGER fail_transition BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'transition rollback fixture'); END;")
        await #expect(throws: (any Error).self) { try await manager.applySeriesTransition(preview) }
        #expect(try await manager.tasks() == before)
        #expect(try sql(directory, "SELECT COUNT(*) FROM operations;") == operations)
        try sql(directory, "DROP TRIGGER fail_transition;")
        let successor = try await manager.applySeriesTransition(preview)
        #expect(successor.id == preview.successor.id)
        let reopened = try await TaskChampionSession.open(directory: directory)
        #expect(try await reopened.task(id: parent.id).status == "deleted")
        #expect(try await reopened.task(id: parent.id).attributes["mask"] == "X")
        #expect(try await reopened.task(id: child.id).attributes["parent"] == successor.id.uuidString.lowercased())
        #expect(try await reopened.tasks().count == before.count + 1)
        await #expect(throws: (any Error).self) { try await manager.applySeriesTransition(preview) }
    }

    @Test func publicTransitionRejectsNativeChangesAfterCoreValidationWithoutPartialCreation() async throws {
        for identityCollision in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let native = TaskChampionReplica(directory: directory)
            let parent = try await native.create(id: UUID(), attributes: ["status": "recurring", "description": "Original", "due": "4000", "recur": "weekly", "mask": "-"])
            let child = try await native.create(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0", "due": "4000"])
            let race = TransitionRaceReplica(native: native, child: child, identityCollision: identityCollision)
            let manager = TaskManager(replica: race, now: { Date(timeIntervalSince1970: 1000) })
            let preview = try await manager.previewSeriesTransition(id: parent.id, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 2000), firstDue: Date(timeIntervalSince1970: 4000100000), recurrence: "monthly", generatorTimeZone: "UTC"))
            await #expect(throws: (any Error).self) { try await manager.applySeriesTransition(preview) }
            #expect(try await manager.task(id: parent.id) == parent)
            let records = try await manager.tasks()
            if identityCollision {
                #expect(records.first(where: { $0.id == preview.successor.id })?.description == "Concurrent identity")
                #expect(try await manager.task(id: child.id) == child)
            } else {
                #expect(!records.contains(where: { $0.id == preview.successor.id }))
                #expect(try await manager.task(id: child.id).attributes["due"] == "1000")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
    @MainActor func encryptedSuccessorTransitionsMatchIndependentTaskwarriorCalendarGeneration() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawClient = try #require(env["TSK_SYNC_TEST_GENERATOR_23_CLIENT_ID"] ?? env["TSK_SYNC_TEST_CLIENT_ID"])
        let configuration = try SyncConfiguration(serverURL: #require(env["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(env["TSK_SYNC_TEST_SECRET"]))
        let appDirectory = root.appendingPathComponent("app")
        let manager = try await TaskChampionSession.open(directory: appDirectory)
        let taskrc = root.appendingPathComponent("taskrc")
        try """
        data.location=\(root.appendingPathComponent("desktop").path)
        confirmation=no
        recurrence.confirmation=no
        news.version=3.5.0
        recurrence.limit=6
        uda.opaque.type=string
        sync.server.url=\(configuration.serverURL)
        sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
        sync.encryption_secret=\(configuration.encryptionSecret)

        """.write(to: taskrc, atomically: true, encoding: .utf8)
        var commands: [[String: Any]] = []
        func task(_ arguments: [String], generate: Bool = false) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: try #require(env["TSK_TASKWARRIOR_BINARY"]))
            process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=\(generate ? "on" : "off")"] + arguments
            var isolated = env
            isolated["TASKRC"] = taskrc.path; isolated["TASKDATA"] = root.appendingPathComponent("desktop").path
            isolated["TZ"] = "CET-1CEST,M3.5.0/2,M10.5.0/3"
            process.environment = isolated
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output; process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let error = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            commands.append(["arguments": arguments, "generationEnabled": generate, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: error, as: UTF8.self)])
            guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: error, as: UTF8.self)) }
            return data
        }
        defer {
            if let path = env["TSK_SERIES_TRANSITION_PROOF_PATH"], let bytes = try? JSONSerialization.data(withJSONObject: commands, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: URL(fileURLWithPath: path)) }
        }
        let cases: [(String, String, Bool, Bool)] = [
            ("monthly", "2094-03-31T09:00:00Z", false, false),
            ("monthly", "2094-01-31T10:00:00Z", false, false),
            ("2m", "2094-01-31T10:00:00Z", false, false),
            ("P2M", "2094-01-31T10:00:00Z", false, false),
            ("P3M", "2094-01-31T10:00:00Z", false, false),
            ("quarterly", "2094-01-31T10:00:00Z", false, false),
            ("yearly", "2096-02-29T10:00:00Z", false, false),
            ("biannual", "2096-02-29T10:00:00Z", false, false),
            ("P2Y", "2096-02-29T10:00:00Z", false, false),
            ("2years", "2096-02-29T10:00:00Z", true, false),
            ("daily", "2094-03-27T08:00:00Z", false, false),
            ("weekly", "2094-03-22T08:00:00Z", false, false),
            ("weekdays", "2094-03-26T08:00:00Z", false, false),
            ("weekly", "2094-03-22T08:00:00Z", false, true)
        ]
        let formatter = ISO8601DateFormatter()
        let oldDue = try #require(formatter.date(from: "2093-01-01T10:00:00Z"))
        func children(_ records: [TaskRecord], parent: UUID) -> [TaskRecord] {
            records.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parent }.sorted { Int($0.attributes["imask"] ?? "-1")! < Int($1.attributes["imask"] ?? "-1")! }
        }
        for (rule, rawFirst, clearOffsets, finiteUntil) in cases {
            let original = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Old \(rule)", attributes: ["opaque": "parent café e\u{301}", "scheduled": String(Int(oldDue.timeIntervalSince1970 - 7200)), "wait": String(Int(oldDue.timeIntervalSince1970 - 3600))]), firstDue: oldDue, recurrence: "weekly"))
            _ = try await manager.synchronize(using: configuration)
            _ = try task(["sync"])
            _ = try task(["rc.report.list.filter=", "list"], generate: true)
            _ = try task(["sync"])
            _ = try await manager.synchronize(using: configuration)
            let generated = children(try await manager.tasks(), parent: original.id)
            #expect(generated.count == 6)
            let history = try await manager.complete(id: generated[0].id)
            let overdueDate = String(Int(Date().timeIntervalSince1970 - 86400))
            for child in generated[1...2] { _ = try await manager.update(id: child.id, changes: ["due": overdueDate, "scheduled": nil, "wait": nil]) }
            let firstMoved = generated[3]
            _ = try await manager.update(id: firstMoved.id, changes: ["opaque": "occurrence opaque", "scheduled": String(Int(firstMoved.deadline!.timeIntervalSince1970 - 9000))])
            _ = try await manager.synchronize(using: configuration)
            let before = try await manager.tasks()
            let first = try #require(formatter.date(from: rawFirst))
            let setsOffsets = rule == "weekly"
            let draft = TaskSeriesTransitionDraft(effectiveDate: Date(), firstDue: first, recurrence: rule, generatorTimeZone: "Europe/Paris", planned: clearOffsets ? .clear : setsOffsets ? .set(-5400) : .preserve, wait: clearOffsets ? .clear : setsOffsets ? .set(-1800) : .preserve, until: finiteUntil ? first.addingTimeInterval(1209600) : nil)
            let preview = try await manager.previewSeriesTransition(id: original.id, draft: draft)
            #expect(Set(preview.affected.map(\.id)) == Set(generated[3...5].map(\.id)))
            #expect(try await manager.tasks() == before)
            let successor = try await manager.applySeriesTransition(preview)
            #expect(try await manager.task(id: original.id).attributes["mask"] == "+--XXX")
            #expect(try await manager.task(id: generated[0].id) == history)
            _ = try await manager.update(id: generated[1].id, changes: ["description": "Still editable under retired parent"])
            _ = try await manager.complete(id: generated[2].id)
            let reference = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Reference \(rule)", attributes: TaskAttributes(successor.attributes.filter { ["scheduled", "wait", "until"].contains($0.key) })), firstDue: first, recurrence: rule))
            _ = try await manager.synchronize(using: configuration)
            _ = try task(["sync"])
            _ = try task([generated[1].id.uuidString.lowercased(), "done"])
            _ = try task(["rc.report.list.filter=", "list"], generate: true)
            _ = try task(["sync"])
            _ = try await manager.synchronize(using: configuration)
            let reopened = try await TaskChampionSession.open(directory: appDirectory)
            let after = try await reopened.tasks()
            let movedAndGenerated = children(after, parent: successor.id)
            let oracle = children(after, parent: reference.id)
            #expect(movedAndGenerated.count == (finiteUntil ? 4 : 6) && oracle.count == (finiteUntil ? 4 : 6))
            #expect(movedAndGenerated.map(\.deadline) == oracle.map(\.deadline))
            #expect(movedAndGenerated[3].deadline == preview.nextGeneratorDue)
            #expect(Set(movedAndGenerated.prefix(3).map(\.id)) == Set(generated[3...5].map(\.id)))
            #expect(movedAndGenerated[0].attributes["opaque"] == "occurrence opaque")
            for (index, child) in movedAndGenerated.enumerated() {
                let plannedOffset: Double? = clearOffsets ? nil : setsOffsets ? -5400 : (index == 0 ? -9000 : -7200)
                #expect(child.plannedDate?.timeIntervalSince1970 == plannedOffset.map { child.deadline!.timeIntervalSince1970 + $0 })
                #expect(child.waitUntil?.timeIntervalSince1970 == (clearOffsets ? nil : child.deadline!.timeIntervalSince1970 - (setsOffsets ? 1800 : 3600)))
            }
            #expect(try await reopened.task(id: original.id).attributes["mask"] == "+++XXX")
            #expect(try await reopened.task(id: original.id).attributes["opaque"]?.matchesBytes("parent café e\u{301}") == true)
            #expect(try await reopened.task(id: history.id) == history)
            let orphanData = try #require(JSONSerialization.jsonObject(with: task(["+ORPHAN", "export"])) as? [[String: Any]])
            let orphanIDs = Set(orphanData.compactMap { $0["uuid"] as? String })
            #expect(orphanIDs.contains(original.id.uuidString.lowercased()) == orphanIDs.contains(successor.id.uuidString.lowercased()))
            let beforeRepeat = Set(after.map(\.id))
            _ = try task(["rc.report.list.filter=", "list"], generate: true)
            _ = try task(["sync"])
            _ = try await manager.synchronize(using: configuration)
            #expect(Set(try await manager.tasks().map(\.id)) == beforeRepeat)
            #expect(try await manager.task(id: history.id) == history)
            let repeated = try await manager.tasks()
            #expect(repeated.first(where: { $0.id == successor.id })?.status == (finiteUntil ? "deleted" : "recurring"))
            let seriesIDs = Set([original.id, successor.id, reference.id])
            let related = repeated.filter { seriesIDs.contains($0.id) || UUID(uuidString: $0.attributes["parent"] ?? "").map(seriesIDs.contains) == true }
            commands.append(["caseRule": rule, "firstDue": rawFirst, "finiteUntil": finiteUntil, "records": try JSONSerialization.jsonObject(with: JSONEncoder().encode(related))])
        }
    }

    @discardableResult @MainActor private func sql(_ directory: URL, _ query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, query]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit()
        let result = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw TaskManagementError.storage(result) }
        return result
    }
}

private actor TransitionRaceReplica: TaskAtomicTransitionReplica, TaskMutationCoordinatingReplica {
    let native: TaskChampionReplica
    let child: TaskRecord
    let identityCollision: Bool
    init(native: TaskChampionReplica, child: TaskRecord, identityCollision: Bool) { self.native = native; self.child = child; self.identityCollision = identityCollision }
    func tasks() async throws -> [TaskRecord] { try await native.tasks() }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { try await native.create(id: id, attributes: attributes) }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { try await native.update(id: id, changes: changes) }
    func acquireMutationLease() async throws -> any TaskMutationLease { try await native.acquireMutationLease() }
    func updateAtomically(_ updates: [TaskAtomicUpdate]) async throws -> [TaskRecord] { try await native.updateAtomically(updates) }
    func updateAtomically(_ updates: [TaskAtomicUpdate], expecting records: [TaskRecord]) async throws -> [TaskRecord] { try await native.updateAtomically(updates, expecting: records) }
    func commitAtomically(creating: [TaskAtomicCreate], updating: [TaskAtomicUpdate], expecting records: [TaskRecord]) async throws -> [TaskRecord] {
        if identityCollision { _ = try await native.create(id: creating[0].id, attributes: ["status": "pending", "description": "Concurrent identity"]) }
        else { _ = try await native.updateAtomically([TaskAtomicUpdate(id: child.id, expected: child.attributes, changes: ["due": "1000"])]) }
        return try await native.commitAtomically(creating: creating, updating: updating, expecting: records)
    }
}
