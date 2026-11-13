import CryptoKit
import EventKit
import Foundation

struct MigrationTask: Codable {
    let uuid: String
    let title: String
    let date: String?
    let notes: String
    let priority: Int
    let source_url: String
}

struct Manifest: Decodable {
    let version: Int
    let source_sha256: String
    let timezone: String
    let list_name: String
    let reminders: [MigrationTask]
    let manual_series: [Series]

    struct Series: Decodable {
        let unfinished_occurrences: [String]
    }
}

struct Receipt: Codable {
    let manifestSHA256: String
    let calendarID: String
    var saved: [String: String]
}

enum MigrationError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

func checksum(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func parsedDate(_ value: String) throws -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        throw MigrationError.invalid("Invalid migration date: \(value)")
    }
    return date
}

func receiptAt(_ path: URL, hash: String) throws -> Receipt? {
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: path))
    guard receipt.manifestSHA256 == hash else {
        throw MigrationError.invalid("The manifest changed after staging. Use the original bundle and receipt.")
    }
    return receipt
}

func saveReceipt(_ receipt: Receipt, at path: URL) throws {
    try JSONEncoder().encode(receipt).write(to: path, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
}

func sampleTasks(_ manifest: Manifest) -> [MigrationTask] {
    let prefix = "tsk-sorted-migration://sample/\(manifest.source_sha256)/"
    return [
        MigrationTask(uuid: "sample-notes", title: "Migration sample — notes, café & links", date: nil,
                      notes: "First line\nSecond line: https://example.org/?a=1&b=2\n\nProject: Migration sample\nTags: sample, café\nTaskwarrior UUID: sample-notes",
                      priority: 1, source_url: prefix + "notes"),
        MigrationTask(uuid: "sample-time", title: "Migration sample — timed", date: "2030-01-15T13:37:00Z",
                      notes: "Check the time against the bundle time zone.\nTaskwarrior UUID: sample-time",
                      priority: 0, source_url: prefix + "time"),
        MigrationTask(uuid: "sample-midnight", title: "Migration sample — midnight", date: "2030-01-15T23:00:00Z",
                      notes: "Check midnight when using Europe/Paris.\nTaskwarrior UUID: sample-midnight",
                      priority: 0, source_url: prefix + "midnight")
    ]
}

@available(macOS 14.0, *)
@MainActor
func reminders(in calendar: EKCalendar, store: EKEventStore) async throws -> [EKReminder] {
    try await withCheckedThrowingContinuation { continuation in
        store.fetchReminders(matching: store.predicateForReminders(in: [calendar])) { reminders in
            if let reminders {
                continuation.resume(returning: reminders)
            } else {
                continuation.resume(throwing: MigrationError.invalid("Reminders could not be fetched; no changes made."))
            }
        }
    }
}

func matches(_ reminder: EKReminder, task: MigrationTask) -> Bool {
    reminder.url?.absoluteString == task.source_url ||
        reminder.notes?.components(separatedBy: "\n").contains("Taskwarrior UUID: \(task.uuid)") == true
}

func verify(_ reminder: EKReminder, task: MigrationTask, calendar: Calendar) throws {
    guard reminder.title == task.title, reminder.notes == task.notes, reminder.priority == task.priority else {
        throw MigrationError.invalid("Staged fields differ for \(task.uuid). Existing reminders are never overwritten.")
    }
    if let value = task.date {
        let expected = try parsedDate(value)
        guard let components = reminder.dueDateComponents, let actual = calendar.date(from: components),
              abs(actual.timeIntervalSince(expected)) < 1 else {
            throw MigrationError.invalid("Staged date differs for \(task.uuid).")
        }
    } else if reminder.dueDateComponents != nil {
        throw MigrationError.invalid("Undated task \(task.uuid) unexpectedly has a date.")
    }
    guard !reminder.hasRecurrenceRules, !reminder.hasAlarms else {
        throw MigrationError.invalid("Unexpected alarm or repeat rule for \(task.uuid).")
    }
}

@available(macOS 14.0, *)
@MainActor
func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let manifestPath = arguments.first else {
        throw MigrationError.invalid("Usage: stage-reminders manifest.json validate|check|sample|verify-sample|apply|verify [--sample-checked]")
    }
    let mode = arguments.dropFirst().first ?? "validate"
    let flags = Array(arguments.dropFirst(2))
    guard ["validate", "check", "sample", "verify-sample", "apply", "verify"].contains(mode),
          flags.allSatisfy({ $0 == "--sample-checked" }) else {
        throw MigrationError.invalid("Unknown mode or option.")
    }
    let manifestURL = URL(fileURLWithPath: manifestPath).standardizedFileURL
    let directory = manifestURL.deletingLastPathComponent()
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
    guard manifest.version == 1, !manifest.list_name.isEmpty,
          let zone = TimeZone(identifier: manifest.timezone) else {
        throw MigrationError.invalid("Unsupported manifest or time zone.")
    }
    guard checksum(try Data(contentsOf: directory.appendingPathComponent("source.json"))) == manifest.source_sha256 else {
        throw MigrationError.invalid("The source archive checksum does not match the manifest.")
    }
    guard Set(manifest.reminders.map(\.uuid)).count == manifest.reminders.count else {
        throw MigrationError.invalid("Duplicate source UUIDs in the manifest.")
    }
    for task in manifest.reminders {
        guard UUID(uuidString: task.uuid) != nil, !task.title.isEmpty,
              task.source_url == "tsk-sorted-migration://task/" + task.uuid,
              [0, 1, 5, 9].contains(task.priority) else {
            throw MigrationError.invalid("Invalid task fields for \(task.uuid).")
        }
        if let date = task.date { _ = try parsedDate(date) }
    }
    print("Validated \(manifest.reminders.count) unfinished tasks; \(manifest.manual_series.count) series require manual setup. Time zone: \(manifest.timezone).")
    if mode == "validate" { return }
    let hash = checksum(manifestData)
    if mode == "apply" {
        let sampleReceipt = try receiptAt(directory.appendingPathComponent("receipt-sample.json"), hash: hash)
        guard flags.contains("--sample-checked"), sampleReceipt?.saved.count == 3 else {
            throw MigrationError.invalid("Run sample, import its list into Sorted, check notes/dates/priority, then use apply --sample-checked.")
        }
    }
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if mode == "check", status != .fullAccess {
        throw MigrationError.invalid("Reminders authorization: \(status.rawValue). Run sample locally from Terminal to request access.")
    }
    let store = EKEventStore()
    if status == .notDetermined, ["sample", "apply"].contains(mode) {
        guard try await store.requestFullAccessToReminders() else {
            throw MigrationError.invalid("Reminders access was not granted.")
        }
    } else if status != .fullAccess {
        throw MigrationError.invalid("Grant Reminders access in System Settings → Privacy & Security → Reminders, then run locally from Terminal.")
    }
    if mode == "check" {
        print("Reminders access available. \(store.calendars(for: .reminder).count) lists visible. No changes made.")
        return
    }
    let isSample = ["sample", "verify-sample"].contains(mode)
    let tasks = isSample ? sampleTasks(manifest) : manifest.reminders
    let listName = manifest.list_name + (isSample ? " · sample" : "")
    let receiptURL = directory.appendingPathComponent(isSample ? "receipt-sample.json" : "receipt.json")
    let previous = try receiptAt(receiptURL, hash: hash)
    let calendars = store.calendars(for: .reminder).filter { $0.title == listName }
    guard calendars.count <= 1 else {
        throw MigrationError.invalid("Multiple lists named \(listName); resolve the ambiguity before retrying.")
    }
    let calendar: EKCalendar
    if let saved = previous {
        guard let found = store.calendar(withIdentifier: saved.calendarID), found.title == listName else {
            throw MigrationError.invalid("The original staging list is missing or renamed. Do not recreate it; use the receipt to reconcile the transfer.")
        }
        calendar = found
    } else if let found = calendars.first {
        calendar = found
    } else {
        guard ["sample", "apply"].contains(mode) else {
            throw MigrationError.invalid("No staging list exists for this bundle.")
        }
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            throw MigrationError.invalid("No default writable Reminders account. Configure one in Reminders before staging.")
        }
        calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listName
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
    }
    guard calendar.allowsContentModifications else {
        throw MigrationError.invalid("The staging list is read-only.")
    }
    var dateCalendar = Calendar(identifier: .gregorian)
    dateCalendar.timeZone = zone
    let existing = try await reminders(in: calendar, store: store)
    var receipt = previous ?? Receipt(manifestSHA256: hash, calendarID: calendar.calendarIdentifier, saved: [:])
    var missing: [MigrationTask] = []
    var alreadySaved = 0
    for task in tasks {
        let found = existing.filter { matches($0, task: task) }
        guard found.count <= 1 else {
            throw MigrationError.invalid("Duplicate staging reminders for \(task.uuid); no changes made.")
        }
        if let reminder = found.first {
            try verify(reminder, task: task, calendar: dateCalendar)
            receipt.saved[task.uuid] = reminder.calendarItemIdentifier
            alreadySaved += 1
        } else if receipt.saved[task.uuid] != nil {
            if mode.hasPrefix("verify") {
                throw MigrationError.invalid("Previously staged reminder \(task.uuid) is missing. Inspect Sorted and the receipt; do not recreate blindly.")
            }
            print("Already staged but now absent: \(task.uuid); will not recreate.")
            alreadySaved += 1
        } else {
            missing.append(task)
        }
    }
    if mode.hasPrefix("verify") {
        guard missing.isEmpty else {
            throw MigrationError.invalid("\(missing.count) tasks have not been staged.")
        }
        print("Verified \(tasks.count) staged reminders, including completed source reminders. This does not verify fields inside Sorted.")
        return
    }
    try saveReceipt(receipt, at: receiptURL)
    var created: [(String, EKReminder)] = []
    do {
        for task in missing {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = task.title
            reminder.notes = task.notes
            reminder.priority = task.priority
            reminder.url = URL(string: task.source_url)
            if let value = task.date {
                let date = try parsedDate(value)
                let components = dateCalendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: date)
                reminder.startDateComponents = components
                reminder.dueDateComponents = components
            }
            try store.save(reminder, commit: false)
            created.append((task.uuid, reminder))
        }
        try store.commit()
    } catch {
        store.reset()
        throw error
    }
    for (uuid, reminder) in created { receipt.saved[uuid] = reminder.calendarItemIdentifier }
    try saveReceipt(receipt, at: receiptURL)
    print("Created \(created.count); already staged \(alreadySaved). List: \(listName).")
    print("Taskwarrior was not modified. Keep source.json, this manifest and the receipt.")
    if !isSample {
        print("\(manifest.manual_series.count) series still need manual repeat setup. Projects/tags are in notes; see review.md.")
    }
}

@main
struct StageReminders {
    static func main() async {
        do {
            guard #available(macOS 14.0, *) else {
                throw MigrationError.invalid("macOS 14 or newer is required.")
            }
            try await run()
        } catch {
            FileHandle.standardError.write(Data("Migration staging failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
