import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func rawExpressionQueriesMatchRealTaskwarrior350AcrossSearchModifiersAndBooleanForms() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    struct Fixture: Decodable { let records: [TaskRecord] }
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../Core/Tests/TskCoreTests/Fixtures/raw-taskwarrior-3.5.0.json")
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: source))
    let replica = TaskChampionReplica(directory: directory)
    for task in fixture.records { _ = try await replica.create(id: task.id, attributes: task.attributes) }
    let manager = TaskManager(replica: replica)
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nconfirmation=no\nregex=1\nsearch.case.sensitive=1\n".write(to: config, atomically: true, encoding: .utf8)
    func task(_ arguments: [String]) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import json,subprocess,sys; result=subprocess.run(json.load(sys.stdin),stdout=subprocess.PIPE);sys.stdout.buffer.write(result.stdout);sys.exit(result.returncode)"]
        let input = Pipe()
        process.standardInput = input
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = directory.path
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode([binary, "rc:\(config.path)", "rc.recurrence=off"] + arguments))
        try input.fileHandleForWriting.close()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
    #expect(String(decoding: try task(["_version"]).1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    let cases: [(String, [String])] = [
        ("", []),
        ("project:Work", ["project:Work"]),
        ("project:", ["project:"]),
        ("project.not:", ["project.not:"]),
        ("status:PENDING", ["status:PENDING"]),
        ("status:p", ["status:p"]),
        ("status.is:PENDING", ["status.is:PENDING"]),
        ("project.not:Work", ["project.not:Work"]),
        ("project.is:Work", ["project.is:Work"]),
        ("project.equals:Work", ["project.equals:Work"]),
        ("project.isnt:Work", ["project.isnt:Work"]),
        ("project.none:", ["project.none:"]),
        ("project.any:", ["project.any:"]),
        ("project.below:Work", ["project.below:Work"]),
        ("project.above:Work", ["project.above:Work"]),
        ("project.by:Work", ["project.by:Work"]),
        ("project.startswith:Work", ["project.startswith:Work"]),
        ("project.left:Work", ["project.left:Work"]),
        ("project.endswith:work", ["project.endswith:work"]),
        ("project.right:work", ["project.right:work"]),
        ("project.has:'Work|Art'", ["project.has:Work|Art"]),
        ("project.contains:Work", ["project.contains:Work"]),
        ("project.hasnt:Work", ["project.hasnt:Work"]),
        ("description:Alpha", ["description:Alpha"]),
        ("description.has:Alpha", ["description.has:Alpha"]),
        ("Alpha", ["Alpha"]),
        ("/Alpha/", ["/Alpha/"]),
        ("/^alpha/", ["/^alpha/"]),
        ("/Alpha(?= note)/", ["/Alpha(?= note)/"]),
        ("/^(Alpha|Unrelated)/", ["/^(Alpha|Unrelated)/"]),
        ("/café/", ["/café/"]),
        ("/cafe\u{301}/", ["/cafe\u{301}/"]),
        ("project.is:café", ["project.is:café"]),
        ("project.is:cafe\u{301}", ["project.is:cafe\u{301}"]),
        ("+café", ["+café"]),
        ("+cafe\u{301}", ["+cafe\u{301}"]),
        ("+home project:Work", ["+home", "project:Work"]),
        ("(project:Work and +home) xor status:completed", ["(", "project:Work", "and", "+home", ")", "xor", "status:completed"]),
        ("!(project:Work)", ["!(project:Work)"]),
        ("project.is:Work or project.is:Artwork and +home", ["project.is:Work", "or", "project.is:Artwork", "and", "+home"]),
        ("not project:Work", ["not", "project:Work"]),
        ("description.has:'Alpha in an annotation'", ["description.has:Alpha in an annotation"]),
        ("status:completed", ["status:completed"])
    ]
    for (expression, arguments) in cases {
        let (status, output) = try task(arguments + ["export"])
        #expect(status == 0, "Taskwarrior rejected \(arguments)")
        let exported = try #require(JSONSerialization.jsonObject(with: output) as? [[String: Any]])
        let expected = Set(exported.compactMap { $0["uuid"] as? String })
        let actual = Set(try await manager.tasks(filter: expression).map { $0.id.uuidString.lowercased() })
        #expect(actual == expected, "Expression: \(expression)")
    }
    #expect(try task(["/(?<=A)lpha/", "export"]).0 != 0)
    let original = try #require(fixture.records.first)
    _ = try await manager.complete(id: original.id)
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await reopened.tasks(filter: "status:completed").contains { $0.id == original.id })
    #expect(try await reopened.task(id: original.id).attributes["score"] == "0")
}
