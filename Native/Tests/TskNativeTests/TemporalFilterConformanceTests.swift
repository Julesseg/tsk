import Foundation
import Testing
import TskCore
import TskNative

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func relativeDateAndVirtualTagQueriesAgreeWithPinnedTaskwarrior350() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nconfirmation=no\nweekstart=sunday\ndue=7\nregex=1\nsearch.case.sensitive=1\n".write(to: config, atomically: true, encoding: .utf8)
    func task(_ arguments: [String]) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import json,subprocess,sys; r=subprocess.run(json.load(sys.stdin),stdout=subprocess.PIPE);sys.stdout.buffer.write(r.stdout);sys.exit(r.returncode)"]
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = directory.path
        environment["TZ"] = "UTC"
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode([binary, "rc:\(config.path)", "rc.recurrence=off"] + arguments))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        while process.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
    let version = try task(["_version"])
    #expect(String(decoding: version.1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), calendar: calendar)
    let replica = TaskChampionReplica(directory: directory)
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let day = calendar.startOfDay(for: now)
    func seed(_ name: String, _ attributes: TaskAttributes = [:]) async throws -> TaskRecord {
        var attributes = attributes
        attributes["description"] = name
        if attributes["status"] == nil { attributes["status"] = "pending" }
        attributes["entry"] = "\(Int(now.timeIntervalSince1970) - 1000)"
        return try await replica.create(id: UUID(), attributes: attributes)
    }
    func seconds(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }
    _ = try await seed("No dates")
    _ = try await seed("Yesterday", ["due": seconds(day.addingTimeInterval(-3600))])
    _ = try await seed("Midnight", ["due": seconds(day), "tag_home": "", "priority": "H"])
    _ = try await seed("Later today", ["due": seconds(day.addingTimeInterval(86399))])
    _ = try await seed("Completed", ["status": "completed", "end": seconds(now), "due": seconds(day), "start": seconds(now.addingTimeInterval(-3600)), "annotation_1792015200": "A note"])
    _ = try await seed("Deleted", ["status": "deleted", "due": seconds(day)])
    _ = try await seed("Template", ["status": "recurring", "recur": "1d", "due": seconds(day), "mask": ""])
    _ = try await seed("Waiting", ["wait": seconds(now.addingTimeInterval(86400)), "due": seconds(day.addingTimeInterval(86400))])
    _ = try await seed("Planned later", ["scheduled": seconds(now.addingTimeInterval(86400))])
    _ = try await seed("Scheduled earlier", ["scheduled": seconds(now.addingTimeInterval(-3600))])
    _ = try await seed("Horizon edge", ["due": seconds(day.addingTimeInterval(7 * 86400))])
    _ = try await seed("Horizon inside", ["due": seconds(day.addingTimeInterval(7 * 86400 - 1))])
    let prerequisite = try await seed("Prerequisite", ["project": "Other"])
    let child = try await seed("Dependent", ["dep_\(prerequisite.id.uuidString.lowercased())": "", "project": "Work"])
    _ = try await seed("Instance", ["parent": prerequisite.id.uuidString.lowercased(), "recur": "1d"])
    _ = try await seed("Presence", ["project": "", "until": "", "priority": "", "last": ""])
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let named = ["today", "yesterday", "tomorrow", "sod", "sopd", "sond", "eopd", "eod", "eond", "sow", "sopw", "sonw", "eopw", "eow", "eonw", "soww", "sopww", "sonww", "eopww", "eoww", "eonww", "som", "sopm", "sonm", "eopm", "eom", "eonm", "soq", "sopq", "sonq", "eopq", "eoq", "eonq", "soy", "sopy", "sony", "eopy", "eoy", "eony", "monday", "sunday", "january", "december", "1st", "31st", "later", "someday", "easter", "eastermonday", "goodfriday", "ascension", "pentecost", "midsommar", "midsommarafton", "juhannus"]
    for name in named {
        let calculated = try task(["calc", name])
        #expect(calculated.0 == 0)
        let text = String(decoding: calculated.1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let date = try #require(formatter.date(from: text), "Cannot decode CLI date \(name): \(text)")
        _ = try await seed("Named \(name)", ["due": seconds(date)])
    }
    var cases = named.map { ("due.is:\($0)", ["due.is:\($0)"]) }
    cases += [
        ("+ACTIVE or status:completed", ["+ACTIVE", "or", "status:completed"]),
        ("-ACTIVE", ["-ACTIVE"]),
        ("due:today", ["due:today"]), ("due.not:today", ["due.not:today"]),
        ("due.before:tomorrow", ["due.before:tomorrow"]), ("due.after:yesterday", ["due.after:yesterday"]),
        ("due.by:today", ["due.by:today"]), ("due.none:", ["due.none:"]), ("due.any:", ["due.any:"]),
        ("due.before:now", ["due.before:now"]), ("due.before:now+1d", ["due.before:now+1d"]),
        ("due.after:now-1week", ["due.after:now-1week"]), ("due.before:today+P1D", ["due.before:today+P1D"]),
        ("due.before:1month", ["due.before:1month"]), ("due.isnt:tomorrow", ["due.isnt:tomorrow"]),
        ("due.has:'T00:00'", ["due.has:T00:00"]), ("scheduled.none:", ["scheduled.none:"]),
        ("due.is:0", ["due.is:0"]), ("due.below:0", ["due.below:0"]), ("due.by:", ["due.by:"]),
        ("(due:today or +BLOCKED) and status:pending", ["(", "due:today", "or", "+BLOCKED", ")", "and", "status:pending"])
    ]
    for name in ["BLOCKED", "UNBLOCKED", "BLOCKING", "READY", "DUE", "DUETODAY", "TODAY", "YESTERDAY", "TOMORROW", "OVERDUE", "WEEK", "MONTH", "QUARTER", "YEAR", "ACTIVE", "SCHEDULED", "CHILD", "INSTANCE", "UNTIL", "ANNOTATED", "TAGGED", "PARENT", "TEMPLATE", "WAITING", "PENDING", "COMPLETED", "DELETED", "PROJECT", "PRIORITY"] {
        cases.append(("+" + name, ["+" + name])); cases.append(("-" + name, ["-" + name]))
    }
    for (expression, arguments) in cases {
        let result = try task(arguments + ["export"])
        #expect(result.0 == 0, "CLI rejected \(arguments)")
        let exported = try #require(JSONSerialization.jsonObject(with: result.1) as? [[String: Any]])
        let expected = Set(exported.compactMap { $0["uuid"] as? String })
        let actual = Set(try await manager.tasks(filter: expression).map { $0.id.uuidString.lowercased() })
        #expect(actual == expected, "\(expression)")
    }
    let saved = try await manager.addDependency(id: child.id, prerequisiteID: prerequisite.id)
    _ = try await manager.complete(id: prerequisite.id)
    #expect(try await manager.tasks(filter: "+BLOCKED").allSatisfy { $0.id != saved.id })
    #expect(try await manager.tasks(filter: "+READY").contains { $0.id == saved.id })
}
