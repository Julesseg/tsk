import Foundation
import Testing
import TskCore
import TskNative

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func typedNumericFiltersAgreeWithPinnedTaskwarriorAndReopenedSavedViews() async throws {
    let fixture = try TypedFilterFixture()
    defer { fixture.remove() }
    let manager = TaskChampionSession.makeManager(directory: fixture.directory)
    _ = try await manager.saveAttributeDefinition(name: "score", type: .numeric)
    let replica = TaskChampionReplica(directory: fixture.directory)
    for value in [nil, "", "-2", "0", "0.1", "2", "10", "100", "10000000"] as [String?] {
        var attributes: TaskAttributes = ["description": "Score \(value ?? "missing")", "status": "pending", "entry": "1792144800", "foreign": "keep"]
        if let value { attributes["score"] = value }
        _ = try await replica.create(id: UUID(), attributes: attributes)
    }
    let expressions = ["score:0", "score:'1'", "score:'0'", "score.is:0", "score.isnt:0", "score.not:0", "score.below:0", "score.above:0", "score.by:0", "score.none:", "score.any:", "score.below:", "score.above:", "score.by:", "score.is:0.1", "score.is:'0.1'", "score.above:0.1", "score.below:2", "score.by:2", "score.is:1e2", "score.is:+2", "score.has:'^0'", "score.has:1e", "score.has:'1e'", "score.hasnt:'^0'", "score.left:1", "score.right:0"]
    for expression in expressions { try await fixture.compare(expression, manager: manager) }
    let saved = try await manager.saveView(name: "Typed scores", expression: "score.above:2")
    let reopened = TaskChampionSession.makeManager(directory: fixture.directory)
    #expect(try await reopened.savedViews() == [saved])
    #expect(try await reopened.tasks(filter: saved.expression).count == 3)
}

@MainActor
private final class TypedFilterFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let config: URL
    let binary: String

    init() throws {
        binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
        config = directory.appendingPathComponent("taskrc")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "data.location=\(directory.path)\nconfirmation=no\nregex=1\nsearch.case.sensitive=1\nuda.score.type=numeric\nuda.effort.type=duration\nuda.review.type=date\nuda.note.type=string\nuda.reference.type=uuid\nuda.rating.type=string\nuda.rating.values=low,mid,high\nuda.spelling.type=string\nuda.spelling.values=é,e\u{301}\n".write(to: config, atomically: true, encoding: .utf8)
        let version = try task(["_version"])
        #expect(String(decoding: version, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func compare(_ expression: String, manager: TaskManager) async throws {
        let data = try task([expression, "_uuids"])
        let expected = Set(String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init))
        let actual = Set(try await manager.tasks(filter: expression).map { $0.id.uuidString.lowercased() })
        #expect(actual == expected, "\(expression)")
    }

    func task(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import json,subprocess,sys; r=subprocess.run(json.load(sys.stdin),stdout=subprocess.PIPE,stderr=subprocess.PIPE);sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr if r.returncode else b'');sys.exit(r.returncode)"]
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = directory.path
        environment["TZ"] = "UTC"
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode([binary, "rc:\(config.path)", "rc.recurrence=off"] + arguments))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        while process.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "CLI rejected \(arguments)")
        return data
    }
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func typedDurationFiltersMatchPinnedMissingZeroNegativeAndModifierBehavior() async throws {
    let fixture = try TypedFilterFixture()
    defer { fixture.remove() }
    let manager = TaskChampionSession.makeManager(directory: fixture.directory)
    _ = try await manager.saveAttributeDefinition(name: "effort", type: .duration)
    let replica = TaskChampionReplica(directory: fixture.directory)
    for value in [nil, "", "-PT1H", "PT0S", "PT30M", "PT1H", "PT2H", "P1D"] as [String?] {
        var attributes: TaskAttributes = ["description": "Effort \(value ?? "missing")", "status": "pending", "entry": "1792144800"]
        if let value { attributes["effort"] = value }
        _ = try await replica.create(id: UUID(), attributes: attributes)
    }
    for expression in ["effort:1h", "effort.is:60min", "effort.isnt:PT1H", "effort.not:1h", "effort.below:1h", "effort.above:1h", "effort.by:1h", "effort.none:", "effort.any:", "effort.is:PT0S", "effort.below:PT0S", "effort.above:PT0S", "effort.by:PT0S", "effort.is:0", "effort.below:0", "effort.above:0", "effort.by:0", "effort.has:'H'", "effort.hasnt:'H'", "effort.left:'P'", "effort.right:'H'", "effort.is:'PT1H'", "effort.is:'3600'", "effort.is:'0'"] { try await fixture.compare(expression, manager: manager) }
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func typedStringUUIDDateAndPriorityQueriesMatchPinnedClientAndLocalOrdering() async throws {
    let fixture = try TypedFilterFixture()
    defer { fixture.remove() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskChampionSession.makeManager(directory: fixture.directory, calendar: calendar)
    for (name, type) in [("note", TaskAttributeType.string), ("reference", .uuid), ("review", .date)] {
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
    }
    _ = try await manager.saveAttributeDefinition(name: "rating", type: .string, values: ["low", "mid", "high"])
    _ = try await manager.saveAttributeDefinition(name: "spelling", type: .string, values: ["é", "e\u{301}"])
    let replica = TaskChampionReplica(directory: fixture.directory)
    let values: [[String?]] = [
        [nil, nil, nil, nil, nil, nil],
        ["", "", "", "", "", ""],
        ["Café", "ABCDEF12", "1792108800", "H", "low", "é"],
        ["Cafe\u{301}", "abcdef12", "1792144800", "M", "mid", "e\u{301}"],
        ["Prefix text", "abcdef12-1234-1234-1234-123456789012", "1792195199", "L", "high", nil],
        ["Other", "12345678", "0", "?", "foreign", nil]
    ]
    for (index, row) in values.enumerated() {
        var attributes: TaskAttributes = ["description": "Typed fixture \(index)", "status": "pending", "entry": "1792144800", "foreign": "keep"]
        for (name, value) in zip(["note", "reference", "review", "priority", "rating", "spelling"], row) {
            if let value { attributes[name] = value }
        }
        _ = try await replica.create(id: UUID(), attributes: attributes)
    }
    let expressions = [
        "note:Café", "note:Cafe\u{301}", "note.left:Prefix", "note.right:text", "note.has:'é'", "note.none:",
        "reference:abcdef12", "reference.is:ABCDEF12", "reference.isnt:abcdef12", "reference.not:abcdef12", "reference.none:", "reference.any:", "reference.below:abcdef12", "reference.above:abcdef12", "reference.by:abcdef12", "reference.left:'12'", "reference.right:'12'", "reference.has:'AB'",
        "review:2026-10-16", "review.is:2026-10-16T10:00:00Z", "review.before:2026-10-17", "review.after:2026-10-16", "review.by:2026-10-16T10:00:00Z", "review.none:", "review.any:", "review.has:'T10'", "review.left:'T10'", "review.right:'T10'", "review.not:2026-10-16",
        "priority.above:M", "priority.below:M", "priority.by:M", "priority.above:", "priority.below:", "priority.by:", "priority.is:H", "priority.none:",
        "rating.above:mid", "rating.below:mid", "rating.by:mid", "rating.above:", "rating.by:", "rating.is:high", "rating:none", "spelling.above:é", "spelling.below:é", "spelling.is:e\u{301}"
    ]
    for expression in expressions { try await fixture.compare(expression, manager: manager) }
}

@Test func nativeTypedSavedMembershipChangesDurablyAndInvalidImportsRemainRecoverable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskChampionSession.makeManager(directory: directory, calendar: calendar)
    for (name, type) in [("note", TaskAttributeType.string), ("score", .numeric), ("effort", .duration), ("review", .date), ("reference", .uuid)] {
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
    }
    let ordered = try await manager.saveAttributeDefinition(name: "rating", type: .string, values: ["high", "mid", "low", ""])
    let task = try await manager.create(TaskDraft(description: "Typed native task", attributes: ["note": "Review it", "score": "2", "effort": "2h", "review": "2026-10-16T10:00:00Z", "reference": "abcdef12", "rating": "high", "unknown_é": "composed", "unknown_e\u{301}": "decomposed"]))
    let view = try await manager.saveView(name: "Typed membership", expression: "score.above:1 and effort.by:PT2H and review:2026-10-16 and reference:abcdef12 and note:Review and rating.above:mid")
    #expect(try await manager.tasks(filter: view.expression).map(\.id) == [task.id])
    _ = try await manager.updateUserAttributes(id: task.id, changes: ["score": "1"])
    let reopened = TaskChampionSession.makeManager(directory: directory, calendar: calendar)
    #expect(try await reopened.savedViews() == [view])
    #expect(try await reopened.attributeDefinitions().contains(ordered))
    #expect(try await reopened.tasks(filter: view.expression).isEmpty)
    _ = try await reopened.updateUserAttributes(id: task.id, changes: ["score": "3"])
    #expect(try await manager.tasks(filter: view.expression).map(\.id) == [task.id])
    let raw = TaskChampionReplica(directory: directory)
    _ = try await raw.update(id: task.id, changes: ["score": "invalid imported value"])
    await #expect(throws: TaskFilterError.invalidStoredValue(task.id, "score", .numeric)) { try await reopened.tasks(filter: view.expression) }
    _ = try await reopened.update(id: task.id, changes: ["description": "Preserved while repairing"])
    #expect(try await manager.task(id: task.id).attributes["score"] == "invalid imported value")
    _ = try await reopened.updateUserAttributes(id: task.id, changes: ["score": "5"])
    #expect(try await manager.tasks(filter: view.expression).map(\.id) == [task.id])
    try await reopened.deleteAttributeDefinition(name: "score")
    await #expect(throws: TaskFilterError.unknownAttribute("score")) { try await manager.tasks(filter: view.expression) }
    let saved = try await manager.task(id: task.id)
    #expect(saved.attributes["score"] == "5")
    #expect(saved.attributes["unknown_é"] == "composed")
    #expect(saved.attributes["unknown_e\u{301}"] == "decomposed")
}
