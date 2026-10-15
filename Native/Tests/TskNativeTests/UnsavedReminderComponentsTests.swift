#if canImport(EventKit)
import Foundation
import EventKit
import Testing
import TskCore
import TskNative

@MainActor
@Test func unsavedOwnedEventKitComponentsImportAtTheSameDurableCanonicalAnchor() async throws {
    let eventStore = EKEventStore()
    let owned = EKReminder(eventStore: eventStore)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let anchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 2, day: 6, hour: 9, minute: 0, second: 0)
    owned.startDateComponents = anchor
    owned.dueDateComponents = anchor
    let snapshot = ReminderSnapshot(listID: "owned", title: "Unsaved owned components", start: owned.startDateComponents, due: owned.dueDateComponents, recurrenceDescription: #"[{"calendar":"gregorian","endCount":0,"endDate":null,"firstDayOfWeek":2,"frequency":1,"interval":1,"monthdays":[],"months":[],"positions":[],"weekdays":[],"yeardays":[],"yearweeks":[]}]"#, sourceType: 0)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let result = try await manager.copyReminders(from: OwnedUnsavedReminderSource(snapshot: snapshot), mappings: [ReminderListMapping(listID: "owned", project: "")])
    let task = try #require(result.imported.first)
    #expect(result.failures.isEmpty && result.skipped.isEmpty)
    #expect(task.attributes["due"] == "1896598800")
    #expect(task.attributes["scheduled"] == "1896598800")
    #expect(try await TaskChampionSession.makeManager(directory: directory).task(id: task.id) == task)
}

private struct OwnedUnsavedReminderSource: ReminderSource {
    let snapshot: ReminderSnapshot
    func lists() async throws -> [ReminderList] { [ReminderList(id: "owned", title: "Unsaved synthetic object")] }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] { [snapshot] }
}
#endif
