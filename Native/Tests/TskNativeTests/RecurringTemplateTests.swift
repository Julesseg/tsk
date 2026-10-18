import Foundation
import Testing
import TskCore
import TskNative

@Suite(.serialized)
struct RecurringTemplateTests {

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
@MainActor func nativeTemplatesRoundTripThroughTheDesignatedTaskwarriorGeneratorAtCalendarBoundaries() async throws {
    let environment = ProcessInfo.processInfo.environment
    let binary = try #require(environment["TSK_TASKWARRIOR_BINARY"])
    let rawClient = try #require(environment["TSK_SYNC_TEST_GENERATOR_20_CLIENT_ID"] ?? environment["TSK_SYNC_TEST_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let server = try #require(environment["TSK_SYNC_TEST_URL"])
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let configuration = try SyncConfiguration(serverURL: server, clientID: client, encryptionSecret: secret)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let appDirectory = root.appendingPathComponent("app")
    let manager = try await TaskChampionSession.open(directory: appDirectory)
    let formatter = ISO8601DateFormatter()
    let cases: [(rule: String, first: String, until: String?, expected: [String])] = [
        ("weekly", "2094-01-01T10:00:00Z", nil, ["20940101T100000Z", "20940108T100000Z", "20940115T100000Z"]),
        ("daily", "2094-03-27T08:00:00Z", nil, ["20940327T080000Z", "20940328T080000Z", "20940329T080000Z"]),
        ("monthly", "2094-01-31T10:00:00Z", nil, ["20940131T100000Z", "20940228T100000Z", "20940328T090000Z"]),
        ("2m", "2094-01-31T10:00:00Z", nil, ["20940131T100000Z", "20940331T090000Z", "20940531T090000Z"]),
        ("P2M", "2094-01-31T10:00:00Z", nil, ["20940131T100000Z", "20940330T220000Z", "20940530T220000Z"]),
        ("P3M", "2094-01-31T10:00:00Z", nil, ["20940131T100000Z", "20940429T220000Z", "20940729T220000Z"]),
        ("quarterly", "2094-01-31T10:00:00Z", nil, ["20940131T100000Z", "20940430T090000Z", "20940730T090000Z"]),
        ("yearly", "2096-02-29T10:00:00Z", nil, ["20960229T100000Z", "20970228T100000Z", "20980228T100000Z"]),
        ("weekly", "2094-01-01T10:00:00Z", "2094-01-03T10:00:00Z", ["20940101T100000Z", "20940108T100000Z"])
    ]
    var templates: [TaskRecord] = []
    for fixture in cases {
        let first = try #require(formatter.date(from: fixture.first))
        var attributes: TaskAttributes = ["opaque": "preserve \(fixture.rule)", "scheduled": String(Int(first.timeIntervalSince1970 - 7200)), "wait": String(Int(first.timeIntervalSince1970 - 3600))]
        if let until = fixture.until, let date = formatter.date(from: until) { attributes["until"] = String(Int(date.timeIntervalSince1970)) }
        templates.append(try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Generated \(fixture.rule)", attributes: attributes), firstDue: first, recurrence: fixture.rule)))
    }
    #expect(try await manager.tasks().count == cases.count)
    #expect(templates.allSatisfy { $0.attributes["mask"] == nil && $0.attributes["parent"] == nil && $0.attributes["imask"] == nil })
    _ = try await manager.synchronize(using: configuration)
    let desktop = root.appendingPathComponent("desktop")
    let taskrc = root.appendingPathComponent("taskrc")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    recurrence.limit=3
    uda.opaque.type=string
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    var commands: [[String: Any]] = []
    func task(_ arguments: [String], generate: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=\(generate ? "on" : "off")"] + arguments
        var isolated = environment
        isolated["TASKRC"] = taskrc.path
        isolated["TASKDATA"] = desktop.path
        isolated["TZ"] = "CET-1CEST,M3.5.0/2,M10.5.0/3"
        process.environment = isolated
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        commands.append(["arguments": arguments, "generationEnabled": generate, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: error, as: UTF8.self)])
        guard process.terminationStatus == 0 else { throw SynchronizationError.failed(String(decoding: error, as: UTF8.self)) }
        return data
    }
    defer {
        if let destination = environment["TSK_RECURRENCE_PROOF_PATH"], let bytes = try? JSONSerialization.data(withJSONObject: commands, options: [.prettyPrinted, .sortedKeys]) {
            try? bytes.write(to: URL(fileURLWithPath: destination))
        }
    }
    #expect(String(decoding: try task(["_version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    _ = try task(["sync"])
    let before = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
    for template in templates {
        #expect(before.contains { $0["uuid"] as? String == template.id.uuidString.lowercased() && $0["status"] as? String == "recurring" })
        #expect(!before.contains { $0["parent"] as? String == template.id.uuidString.lowercased() })
    }
    _ = try task(["rc.report.list.filter=", "list"], generate: true)
    _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    let reopened = try await TaskChampionSession.open(directory: appDirectory)
    let records = try await reopened.tasks()
    if let destination = environment["TSK_RECURRENCE_RECORDS_PATH"], let first = templates.first {
        let recorded = records.filter { $0.id == first.id || $0.attributes["parent"] == first.id.uuidString.lowercased() }
        try JSONEncoder().encode(recorded).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }
    let generated = try #require(JSONSerialization.jsonObject(with: task(["export"])) as? [[String: Any]])
    for (template, fixture) in zip(templates, cases) {
        let children = records.filter { $0.attributes["parent"] == template.id.uuidString.lowercased() }.sorted { (Int($0.attributes["imask"] ?? "") ?? -1) < (Int($1.attributes["imask"] ?? "") ?? -1) }
        #expect(children.count == fixture.expected.count)
        let external = generated.filter { $0["parent"] as? String == template.id.uuidString.lowercased() }.sorted { ($0["imask"] as? Int ?? -1) < ($1["imask"] as? Int ?? -1) }
        #expect(external.compactMap { $0["due"] as? String } == fixture.expected)
        #expect(try await reopened.task(id: template.id).attributes["mask"] == String(repeating: "W", count: fixture.expected.count))
        for (position, child) in children.enumerated() {
            #expect(child.id != template.id)
            #expect(child.attributes["imask"] == String(position))
            #expect(child.attributes["recur"] == fixture.rule)
            #expect(child.attributes["mask"] == nil)
            #expect(child.attributes["opaque"] == "preserve \(fixture.rule)")
            #expect(child.recurrenceInspection?.kind == .occurrence)
            #expect(child.canEdit && child.canComplete)
            let due = try #require(child.deadline)
            #expect(child.plannedDate == due.addingTimeInterval(-7200))
            #expect(child.waitUntil == due.addingTimeInterval(-3600))
            #expect(external.contains { $0["uuid"] as? String == child.id.uuidString.lowercased() })
        }
    }
    _ = try task(["rc.report.list.filter=", "list"], generate: true)
    _ = try task(["sync"])
    _ = try await reopened.synchronize(using: configuration)
    #expect(try await reopened.tasks().filter { $0.attributes["parent"].map { value in templates.contains { $0.id.uuidString.lowercased() == value } } == true }.count == cases.reduce(0) { $0 + $1.expected.count })
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func nativeTemplateCreationRequestsAutomaticSynchronizationWithoutGeneratingAnyChildren() async throws {
    let environment = ProcessInfo.processInfo.environment
    let rawClient = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let url = try #require(environment["TSK_SYNC_TEST_URL"])
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let configuration = try SyncConfiguration(serverURL: url, clientID: client, encryptionSecret: secret)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let appDirectory = directory.appendingPathComponent("app")
    try await SyncConfigurationStore(directory: appDirectory).save(configuration)
    let app = try await TaskChampionSession.open(directory: appDirectory)
    let template = try await app.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Automatic external-generation template", attributes: ["opaque": "automatic retention"]), firstDue: ISO8601DateFormatter().date(from: "2094-02-01T10:00:00Z"), recurrence: "weekly"))
    let peer = try await TaskChampionSession.open(directory: directory.appendingPathComponent("peer"))
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while true {
        let records = try await peer.synchronize(using: configuration)
        if let received = records.first(where: { $0.id == template.id }) {
            #expect(received == template)
            #expect(!records.contains { $0.attributes["parent"] == template.id.uuidString.lowercased() })
            break
        }
        guard ContinuousClock.now < deadline else { throw SynchronizationError.failed("The native template did not automatically reach the real server") }
        try await Task.sleep(for: .milliseconds(50))
    }
}

}
