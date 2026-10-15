import Foundation

public struct ReminderList: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct ReminderListMapping: Sendable {
    public let listID: String
    public let project: String
    public init(listID: String, project: String) { self.listID = listID; self.project = project }
}

public struct ReminderSnapshot: Sendable {
    public let listID: String
    public let title: String
    public let notes: String?
    public let url: String?
    public let priority: Int
    public let start: DateComponents?
    public let due: DateComponents?
    public let isCompleted: Bool
    public let recurrenceDescription: String?

    public init(listID: String, title: String, notes: String? = nil, url: String? = nil, priority: Int = 0,
                start: DateComponents? = nil, due: DateComponents? = nil, isCompleted: Bool = false, recurrenceDescription: String? = nil) {
        self.listID = listID; self.title = title; self.notes = notes; self.url = url; self.priority = priority
        self.start = start; self.due = due; self.isCompleted = isCompleted; self.recurrenceDescription = recurrenceDescription
    }
}

public protocol ReminderSource: Sendable {
    func lists() async throws -> [ReminderList]
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot]
}

public struct ReminderImportItem: Sendable {
    public let title: String
    public let draft: TaskDraft?
    public let reason: String?
}

public struct ReminderImportResult: Sendable {
    public var imported: [TaskRecord] = []
    public var skipped: [ReminderImportItem] = []
    public var failures: [ReminderImportItem] = []
}

public enum ReminderImportError: Error, LocalizedError, Sendable {
    case noLists
    case duplicateList
    case invalidDate
    case invalidPriority
    public var errorDescription: String? {
        switch self {
        case .noLists: "Select at least one Reminders list."
        case .duplicateList: "Select each Reminders list only once."
        case .invalidDate: "The reminder has incomplete or invalid date components. Its dates could not be preserved."
        case .invalidPriority: "The reminder has an unsupported priority value."
        }
    }
}

public extension TaskManager {
    func previewReminderImport(from source: any ReminderSource, mappings: [ReminderListMapping]) async throws -> [ReminderImportItem] {
        guard !mappings.isEmpty else { throw ReminderImportError.noLists }
        guard Set(mappings.map(\.listID)).count == mappings.count else { throw ReminderImportError.duplicateList }
        let reminders = try await source.incompleteReminders(in: mappings.map(\.listID))
        return reminders.compactMap { reminder in
            guard !reminder.isCompleted, let mapping = mappings.first(where: { $0.listID == reminder.listID }) else { return nil }
            if let recurrence = reminder.recurrenceDescription {
                return ReminderImportItem(title: reminder.title, draft: nil, reason: "Recurring reminder left unchanged: verified recurrence conversion is not available for this rule. \(recurrence)")
            }
            do {
                let description = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
                var attributes: TaskAttributes = [:]
                if !mapping.project.isEmpty { attributes["project"] = mapping.project }
                switch reminder.priority {
                case 0: break
                case 1...4: attributes["priority"] = "H"
                case 5: attributes["priority"] = "M"
                case 6...9: attributes["priority"] = "L"
                default: throw ReminderImportError.invalidPriority
                }
                if let start = reminder.start { attributes["scheduled"] = try reminderTimestamp(start) }
                if let due = reminder.due { attributes["due"] = try reminderTimestamp(due) }
                var timestamp = Int64(now().timeIntervalSince1970)
                for text in [reminder.notes, reminder.url].compactMap({ $0 }) where !text.isEmpty {
                    attributes["annotation_\(timestamp)"] = text
                    guard timestamp < Int64.max else { throw TaskManagementError.invalidAnnotationTimestamp }
                    timestamp += 1
                }
                return ReminderImportItem(title: reminder.title, draft: TaskDraft(description: description, attributes: attributes), reason: nil)
            } catch { return ReminderImportItem(title: reminder.title, draft: nil, reason: error.localizedDescription) }
        }
    }

    func copyReminders(from source: any ReminderSource, mappings: [ReminderListMapping]) async throws -> ReminderImportResult {
        let items = try await previewReminderImport(from: source, mappings: mappings)
        var result = ReminderImportResult()
        for item in items {
            guard let draft = item.draft else { result.skipped.append(item); continue }
            do { result.imported.append(try await create(draft)) }
            catch { result.failures.append(ReminderImportItem(title: item.title, draft: nil, reason: error.localizedDescription)) }
        }
        return result
    }
}

private extension TaskManager {
    func reminderTimestamp(_ components: DateComponents) throws -> String {
        guard components.year != nil, components.month != nil, components.day != nil else { throw ReminderImportError.invalidDate }
        var calendar = components.calendar ?? self.calendar
        calendar.timeZone = components.timeZone ?? components.calendar?.timeZone ?? self.calendar.timeZone
        guard let date = calendar.date(from: components), date.timeIntervalSince1970.isFinite,
              abs(date.timeIntervalSince1970) <= 253402300799 else { throw ReminderImportError.invalidDate }
        let units: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
        let actual = calendar.dateComponents(Set(units), from: date)
        guard units.allSatisfy({ unit in components.value(for: unit).map { $0 == actual.value(for: unit) } ?? true }) else { throw ReminderImportError.invalidDate }
        return String(Int64(date.timeIntervalSince1970))
    }
}
