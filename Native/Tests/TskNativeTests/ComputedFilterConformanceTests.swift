import Foundation
import Testing
import TskCore
import TskNative

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func computedUrgencyAndArithmeticAgreeWithActualPinnedClientAcrossRawReplica() async throws {
    let fixture = try TypedFilterFixture()
    defer { fixture.remove() }
    let epoch = Int(Date().timeIntervalSince1970)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskChampionSession.makeManager(directory: fixture.directory, now: { Date(timeIntervalSince1970: Double(epoch)) }, calendar: calendar)
    for (name, type) in [("score", TaskAttributeType.numeric), ("effort", .duration), ("review", .date), ("note", .string), ("reference", .uuid)] {
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
    }
    let replica = TaskChampionReplica(directory: fixture.directory)
    let prerequisite = UUID()
    let rows: [TaskAttributes] = [
        [:], ["project": "Work"], ["start": String(epoch + 10000)], ["start": ""], ["project": ""],
        ["scheduled": String(epoch - 1000)], ["scheduled": String(epoch + 10000)], ["wait": String(epoch + 10000)],
        ["priority": "H"], ["priority": "M"], ["priority": "L"], ["tag_next": ""],
        ["tag_home": ""], ["tag_home": "", "tag_other": ""], ["tag_a": "", "tag_b": "", "tag_c": ""],
        ["annotation_100": "first"], ["annotation_100": "first", "annotation_200": "second"],
        ["due": String(epoch + 30 * 86400)], ["due": String(epoch - 10 * 86400)],
        ["entry": String(epoch - 200 * 86400 - 1000)], ["entry": String(epoch + 2 * 86400 + 1000)],
        ["dep_\(prerequisite.uuidString.lowercased())": "", "project": "Blocked"],
        ["status": "completed", "priority": "H"],
        ["score": "2", "effort": "PT1H", "review": "1792144800", "note": "abc", "reference": "abcdef12"],
        ["score": "0", "effort": "PT0S", "note": "é"],
        ["score": "-2", "effort": "-PT1H", "note": "e\u{301}"],
        ["score": "", "effort": "", "review": "", "note": ""]
    ]
    for (index, row) in rows.enumerated() {
        var attributes: TaskAttributes = ["description": "Computed fixture \(index)", "status": "pending", "entry": String(epoch), "foreign_é": "composed", "foreign_e\u{301}": "decomposed"]
        for (key, value) in row { attributes[key] = value }
        _ = try await replica.create(id: UUID(), attributes: attributes)
    }
    _ = try await replica.create(id: prerequisite, attributes: ["description": "Prerequisite outside project", "status": "pending", "entry": String(epoch), "project": "Other"])
    let expressions = [
        "urgency.is:3.9", "urgency.above:3.9", "urgency.below:0", "urgency.by:0", "urgency.is:0", "urgency.above:4", "urgency.above:10", "urgency.above:15", "urgency.has:'^3'",
        "urgency + 1 > 4.9", "urgency + 1 == 4.9", "urgency + 2 * 3 > 9.9", "urgency / 2 > 1.95", "urgency % 2 > 1.9", "urgency ^ 2 > 15.2", "urgency + -2 > 1.9", "urgency + (-2) > 1.9",
        "urgency - urgency + 7 / 2 == 3", "urgency - urgency + 7.0 / 2 == 3.5", "urgency - urgency + 2 ^ 3 ^ 2 == 512", "urgency - urgency + -2 ^ 2 == -4", "urgency - urgency + 5.5 % 2 == 1.5", "urgency - urgency + pi > 3.14",
        "urgency.above:3+1", "urgency.above:3-1", "urgency > (urgency - urgency + 3.0 + 1.0)",
        "urgency > 0 and priority:M", "urgency > 0 +next", "urgency + 1 < 10 and /fixture/", "urgency > 0 or status:completed", "urgency > 0 xor +home", "!(urgency > 0) and -home", "urgency > 0 and +ACTIVE",
        "project == Work", "project = Wor", "project != Wor", "project !== Work", "priority > M", "priority >= M", "description ~ 'fixture'", "description !~ 'fixture'", "description ~ 'first'",
        "note + 'x' == 'abcx'", "note - 'x' == 'abc-x'", "note * 2 == 'abcabc'", "note == 'é'", "note == 'e\u{301}'", "note < 'z'",
        "score + 1 > 2", "score * 2 == 4", "score <= 0", "score >= 0",
        "effort + 1h == 2h", "effort * 2 == 2h", "effort < 1h", "effort <= PT0S",
        "review.year == 2026", "review.year == 1970", "status = pen", "status = PENDING", "review.month == 10", "review.day == 16", "review.hour == 10", "review - review == PT0S", "review + 1h == 2026-10-16T11:00:00Z", "review < 2026-10-17", "review == 2026-10-16T10:00:00Z",
        "tags.home == home", "annotations.count > 0", "annotations.count + 1 > 2", "reference == abcdef12", "reference = abcdef12"
    ]
    let records = try await manager.tasks()
    var comparisons: [FilterConformanceSelection] = []
    for expression in expressions { comparisons.append(try await fixture.compare(expression, manager: manager)) }
    try writeComputedFilterEvidence("computed-urgency", epoch: epoch, records: records, comparisons: comparisons)
    let saved = try await manager.saveView(name: "Computed default urgency", expression: "project:Blocked and urgency < 0")
    let reopened = TaskChampionSession.makeManager(directory: fixture.directory)
    #expect(try await reopened.savedViews() == [saved])
    await #expect(throws: TaskFilterError.self) { try await reopened.saveView(id: saved.id, name: saved.name, expression: "urgency / 0 > 0") }
    #expect(try await manager.savedViews() == [saved])
    #expect(try await reopened.tasks(filter: saved.expression).count == 1)
    _ = try await reopened.complete(id: prerequisite)
    #expect(try await manager.tasks(filter: saved.expression).isEmpty)
    try await fixture.compare(saved.expression, manager: manager)
    for expression in ["urgency / 0 > 0", "urgency ^ 2.0 > 0", "false and urgency / 0 > 0", "urgency > (3.0 + 1.0)", "score / 2 == 1", "score % 2 == 0", "score ^ 2 == 4", "effort / 1h == 1", "effort - 30min == 30min"] {
        _ = try fixture.task([expression, "_uuids"], expectedFailure: true)
        await #expect(throws: TaskFilterError.self) { try await manager.tasks(filter: expression) }
    }
    for record in try await reopened.tasks() where record.id != prerequisite {
        #expect(record.attributes["foreign_é"] == "composed")
        #expect(record.attributes["foreign_e\u{301}"] == "decomposed")
    }
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func typedExpressionOperationsAgreeWithPinnedConversionAndDOMRules() async throws {
    let fixture = try TypedFilterFixture()
    defer { fixture.remove() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskChampionSession.makeManager(directory: fixture.directory, calendar: calendar)
    for (name, type) in [("score", TaskAttributeType.numeric), ("effort", .duration), ("review", .date), ("note", .string)] {
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
    }
    let replica = TaskChampionReplica(directory: fixture.directory)
    for (index, value) in ["2", "0", "-2", "0.1"].enumerated() {
        _ = try await replica.create(id: UUID(), attributes: ["description": "Operators \(index)", "status": "pending", "entry": "1792144800", "score": value, "effort": "PT1H", "review": "1792144800", "note": "abc", "annotation_1792144800": "note", "tag_home": ""])
    }
    let records = try await manager.tasks()
    var comparisons: [FilterConformanceSelection] = []
    for expression in [
        "score / 2 == 1", "score % 2 == 0", "score ^ 2 == 4", "score + true > 1", "score - true > 0", "score * true > 0",
        "effort - 30min == 30min", "effort / 1h == 1", "effort / 2 == 30min", "effort * 0.5 == 30min", "effort * -0.5 < PT0S", "effort * -0.5 == 4294965496", "effort * -0.5 == P49710DT5H58M16S", "effort / -0.5 == 4294960096", "score + effort == 4294970894", "score + effort == P49710DT7H28M14S", "score - effort == -3602", "true + score == -1", "true * score == -2", "false > true", "true < false", "true >= false", "false <= true", "(true + 2) / 2 == 1", "effort + 2 == PT1H2S", "effort - 2.9 == PT59M58S",
        "review - 1h == 2026-10-16T09:00:00Z", "review - review == PT0S", "review + 1h == 2026-10-16T11:00:00Z", "review + 1.9 == 2026-10-16T10:00:01Z", "review = 2026-10-16", "review.year == 2026", "review.week == 42", "review.weekday == 5", "review.julian == 289",
        "note + 'x' == 'abcx'", "note - x == 'abc-x'", "note * 2 == 'abcabc'", "note == 'abc'", "note ~ '^abc$'", "annotations.1.description == note", "annotations.1.entry == review", "annotations.1.entry.year == 2026", "tags.home == home"
    ] { comparisons.append(try await fixture.compare(expression, manager: manager)) }
    try writeComputedFilterEvidence("typed-expression-operations", epoch: Int(Date().timeIntervalSince1970), records: records, comparisons: comparisons)
}

private func writeComputedFilterEvidence(_ name: String, epoch: Int, records: [TaskRecord], comparisons: [FilterConformanceSelection]) throws {
    guard let path = ProcessInfo.processInfo.environment["TSK_FILTER_EVIDENCE_DIRECTORY"] else { return }
    struct Evidence: Codable {
        let version = "3.5.0"
        let contract = "tsk-taskwarrior-3.5-expression-v1"
        let contextEpoch: Int
        let recordedAtEpoch: Int
        let records: [TaskRecord]
        let cases: [FilterConformanceSelection]
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Evidence(contextEpoch: epoch, recordedAtEpoch: Int(Date().timeIntervalSince1970), records: records, cases: comparisons)).write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
}
