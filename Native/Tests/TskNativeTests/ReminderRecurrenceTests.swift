import Foundation
import Testing
import TskCore
import TskNative

private let recordedWeeklyRule = #"[{"calendar":"gregorian","endCount":0,"endDate":null,"firstDayOfWeek":2,"frequency":1,"interval":1,"monthdays":[],"months":[],"positions":[],"weekdays":[],"yeardays":[],"yearweeks":[]}]"#

private actor RecordedRecurringReminderSource: ReminderMoveSource {
    let directory: URL
    let title: String
    var present = true
    var removalSawDurableTemplate = false
    init(directory: URL, title: String) { self.directory = directory; self.title = title }
    func lists() -> [ReminderList] { [ReminderList(id: "work", title: "Recorded real local source")] }
    func incompleteReminders(in listIDs: [String]) -> [ReminderSnapshot] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 2, day: 6, hour: 9, minute: 0, second: 0)
        var history = anchor; history.month = 1; history.day = 30
        return (present ? [ReminderSnapshot(listID: "work", title: title, notes: "  Fixture notes\nsecond line  ", url: "https://example.com/reminder", priority: 1, start: anchor, due: anchor, recurrenceDescription: recordedWeeklyRule, sourceType: 0)] : []) + [
            ReminderSnapshot(listID: "work", title: "Completed history", start: history, due: history, isCompleted: true, sourceType: 0),
            ReminderSnapshot(listID: "work", title: "Unsupported interval", start: anchor, due: anchor, recurrenceDescription: recordedWeeklyRule.replacingOccurrences(of: "\"interval\":1", with: "\"interval\":2"), sourceType: 0)
        ]
    }
    func moveCandidates(in listIDs: [String]) -> [ReminderMoveCandidate] {
        incompleteReminders(in: listIDs).map { snapshot in ReminderMoveCandidate(snapshot: snapshot, removeSource: { try await self.remove() }) }
    }
    func remove() async throws {
        let fresh = TaskChampionSession.makeManager(directory: directory)
        removalSawDurableTemplate = try await fresh.recurringTemplates().contains { $0.description == title && $0.attributes["recur"] == "1week" && $0.attributes["due"] == "1896598800" && $0.attributes["scheduled"] == "1896598800" }
        guard removalSawDurableTemplate else { throw TaskManagementError.storage("No valid durable template was found") }
        present = false
    }
}

@Test func recordedRecurringReminderReopensAsValidTemplateBeforeAnyContinuousSourceRemoval() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = TaskChampionSession.makeManager(directory: root)
    let copy = RecordedRecurringReminderSource(directory: root, title: "Recorded copy")
    let mappings = [ReminderListMapping(listID: "work", project: "Recurring")]
    let copied = try await manager.copyReminders(from: copy, mappings: mappings)
    #expect(copied.imported.count == 1 && copied.skipped.count == 1)
    #expect(await copy.present)
    let move = RecordedRecurringReminderSource(directory: root, title: "Recorded move")
    let moved = try await manager.moveReminders(from: move, mappings: mappings)
    #expect(moved.imported.count == 1 && moved.removedCount == 1 && moved.skipped.count == 1)
    #expect(await move.removalSawDurableTemplate)
    #expect(await move.present == false)
    let reopened = TaskChampionSession.makeManager(directory: root)
    #expect(try await reopened.recurringTemplates().count == 2)
    for record in copied.imported + moved.imported {
        #expect(try await reopened.task(id: record.id) == record)
        #expect(record.annotations.map(\.text) == ["  Fixture notes\nsecond line  ", "https://example.com/reminder"])
        #expect(record.attributes["priority"] == "H")
        #expect(record.attributes.keys.allSatisfy { !["parent", "imask", "mask", "source", "sourceID", "reminderID"].contains($0) })
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
@MainActor func recurringReminderTemplatesReturnSixCurrentAnchorOccurrencesThroughEncryptedExternalGeneration() async throws {
    let environment = ProcessInfo.processInfo.environment
    let rawClient = try #require(environment["TSK_SYNC_TEST_GENERATOR_34_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let configuration = try SyncConfiguration(serverURL: #require(environment["TSK_SYNC_TEST_URL"]), clientID: client, encryptionSecret: #require(environment["TSK_SYNC_TEST_SECRET"]))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("app")
    let manager = TaskChampionSession.makeManager(directory: app, now: { Date(timeIntervalSince1970: 1792144800) })
    let mappings = [ReminderListMapping(listID: "work", project: "Recurring")]
    let copied = try await manager.copyReminders(from: RecordedRecurringReminderSource(directory: app, title: "Recurring copy"), mappings: mappings)
    let moved = try await manager.moveReminders(from: RecordedRecurringReminderSource(directory: app, title: "Recurring move"), mappings: mappings)
    let templates = copied.imported + moved.imported
    #expect(templates.count == 2 && moved.removedCount == 1)
    _ = try await manager.synchronize(using: configuration)
    let desktop = root.appendingPathComponent("desktop"), taskrc = root.appendingPathComponent("taskrc")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    recurrence.limit=6
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    var proof: [[String: Any]] = []
    func task(_ arguments: [String], generate: Bool = false) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: try #require(environment["TSK_TASKWARRIOR_BINARY"]))
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=\(generate ? "on" : "off")"] + arguments
        var isolated = environment; isolated["TASKRC"] = taskrc.path; isolated["TASKDATA"] = desktop.path; isolated["TZ"] = "America/New_York"
        process.environment = isolated
        let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); let error = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        proof.append(["arguments": arguments, "generation": generate, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: error, as: UTF8.self)])
        guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: error, as: UTF8.self)) }
        return data
    }
    defer { if let path = environment["TSK_REMINDER_RECURRENCE_PROOF_PATH"], let data = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) } }
    #expect(String(decoding: try task(["_version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    _ = try task(["sync"])
    let before = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
    #expect(before.count == 2 && before.allSatisfy { $0["status"] as? String == "recurring" })
    _ = try task(["rc.report.list.filter=", "list"], generate: true)
    _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    let reopened = TaskChampionSession.makeManager(directory: app)
    let expected = ["20300206T090000Z", "20300213T090000Z", "20300220T090000Z", "20300227T090000Z", "20300306T090000Z", "20300313T090000Z"]
    let exported = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
    for template in templates {
        let children = exported.filter { $0["parent"] as? String == template.id.uuidString.lowercased() }.sorted { ($0["imask"] as? Int ?? -1) < ($1["imask"] as? Int ?? -1) }
        #expect(children.compactMap { $0["due"] as? String } == expected)
        #expect(children.compactMap { $0["scheduled"] as? String } == expected)
        #expect(try await reopened.task(id: template.id).attributes["mask"] == "------")
        for child in children {
            let rawID = try #require(child["uuid"] as? String)
            let id = try #require(UUID(uuidString: rawID))
            let returned = try await reopened.task(id: id)
            #expect(returned.recurrenceInspection?.kind == .occurrence && returned.canComplete)
            #expect(returned.attributes["project"] == "Recurring" && returned.attributes["priority"] == "H")
            #expect(returned.annotations.map(\.text) == ["  Fixture notes\nsecond line  ", "https://example.com/reminder"])
        }
    }
    let identities = Set(try await reopened.tasks().map(\.id))
    _ = try task(["rc.report.list.filter=", "list"], generate: true); _ = try task(["sync"])
    _ = try await reopened.synchronize(using: configuration)
    #expect(Set(try await reopened.tasks().map(\.id)) == identities)
    #expect(identities.count == 14)
}

@Test func actualRecurringReplacementCommitFailureKeepsSourceAndExistingTasksForSafeRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Keep existing", attributes: ["opaque": "unchanged"]))
    func sql(_ statement: String) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, statement]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    }
    try sql("CREATE TRIGGER recurring_import_failure BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'owned recurring save fault'); END;")
    let source = RecordedRecurringReminderSource(directory: directory, title: "Recurring fault retry")
    let mappings = [ReminderListMapping(listID: "work", project: "")]
    #expect(try await manager.copyReminders(from: source, mappings: mappings).failures.count == 1)
    #expect(try await manager.moveReminders(from: source, mappings: mappings).stopped)
    #expect(await source.present)
    #expect(try await manager.tasks() == [original])
    try sql("DROP TRIGGER recurring_import_failure;")
    #expect(try await manager.moveReminders(from: source, mappings: mappings).removedCount == 1)
    #expect(await source.removalSawDurableTemplate)
    #expect(try await manager.task(id: original.id) == original)
}
