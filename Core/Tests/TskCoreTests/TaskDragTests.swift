import Foundation
import Testing
import TskCore

@Test func plannerDraggingTracksBothDirectionsAndCommitsOnlyTheLastCrossedIntent() async throws {
    #expect(TaskDragContext.project("caf\u{00e9}") != .project("cafe\u{0301}"))
    #expect(TaskDragContext.project("caf\u{00e9}") == .project("caf\u{00e9}"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1792108800)
    func row(_ name: String, _ intent: TaskScheduledDate?, deadline: String? = nil) -> TaskRecord {
        var draft = TaskDraft(description: name, attributes: ["status": "pending", "project": "Work", "due": deadline ?? "1792400000", "opaque": name])
        draft.setScheduled(intent)
        draft.attributes["description"] = name
        let index = ["carried", "first", "second", "timed", "equal", "fallback", "untimed", "midnight", "history"].firstIndex(of: name)! + 1
        return TaskRecord(id: UUID(uuidString: String(format: "A1060000-0000-0000-0000-%012d", index))!, attributes: draft.attributes)
    }
    let carried = row("carried", .init(date: day.addingTimeInterval(-86400 + 3600), hasTime: true))
    let first = row("first", .init(date: day, hasTime: false))
    let second = row("second", .init(date: day, hasTime: false))
    let timed = row("timed", .init(date: day.addingTimeInterval(3600), hasTime: true))
    let equal = row("equal", .init(date: day.addingTimeInterval(3600), hasTime: true))
    let fallback = row("fallback", nil, deadline: "1792116000")
    let untimed = row("untimed", .init(date: day, hasTime: false))
    let midnight = row("midnight", .init(date: day, hasTime: true))
    var history = row("history", .init(date: day, hasTime: false))
    history.attributes["status"] = "completed"
    history.attributes["end"] = "1792108800"
    let records = [carried, first, second, timed, equal, fallback, untimed, midnight, history]
    let replica = OccurrenceReplica(records: records)
    let manager = TaskManager(replica: replica, now: { day }, calendar: calendar)
    var drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [first.id], context: .day(day), calendar: calendar)
    drag.cross(timed.id)
    drag.cross(equal.id)
    drag.cross(second.id)
    #expect(await replica.records == records)
    #expect(await replica.batches == 0)
    _ = try await manager.drop(drag)
    #expect(try await manager.task(id: first.id).scheduled(calendar: calendar) == first.scheduled(calendar: calendar))
    #expect(try await manager.dayPage(on: day).filter { [first.id, second.id].contains($0.id) }.map(\.id) == [first.id, second.id])
    #expect(await replica.batches == 1)
    let event = CalendarEventSnapshot(calendarID: "work", eventID: "meeting", title: "Meeting", calendarTitle: "Work", start: day.addingTimeInterval(5400), end: day.addingTimeInterval(7200))
    let overnight = CalendarEventSnapshot(calendarID: "work", eventID: "overnight", title: "Overnight", calendarTitle: "Work", start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(3600))
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [first.id], context: .day(day), calendar: calendar)
    drag.cross(event)
    drag.cross(overnight)
    drag.cross(second.id, direction: .upward)
    _ = try await manager.drop(drag)
    #expect(try await manager.dayPage(on: day).filter { [first.id, second.id].contains($0.id) }.map(\.id) == [first.id, second.id])
    for target in [fallback, carried, timed] {
        drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [first.id], context: .day(day), calendar: calendar)
        drag.cross(target.id)
        _ = try await manager.drop(drag)
        let saved = try await manager.task(id: first.id)
        #expect(saved.scheduled(calendar: calendar) == target.plannerDate(calendar: calendar))
        #expect(saved.deadline == first.deadline)
        #expect(saved.attributes["opaque"] == "first")
    }
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [first.id], context: .day(day), calendar: calendar)
    drag.cross(equal.id)
    _ = try await manager.drop(drag)
    #expect(try await manager.dayPage(on: day).filter { $0.plannerDate(calendar: calendar) == timed.scheduled(calendar: calendar) }.map(\.id).last == first.id)
    let blockIDs = [first.id, second.id]
    for target in [carried, equal, fallback, carried, timed, midnight] {
        let before = try await manager.dayPage(on: day)
        let visibleIDs = before.filter { blockIDs.contains($0.id) }.map(\.id)
        let batches = await replica.batches
        drag = try TaskDragSession(tasks: before, ids: blockIDs, context: .day(day), calendar: calendar)
        drag.cross(target.id)
        drag.cross(first.id)
        drag.cross(second.id)
        #expect(drag.lastCrossedID == target.id)
        #expect(drag.ids == visibleIDs)
        #expect(try await manager.dayPage(on: day) == before)
        #expect(await replica.batches == batches)
        _ = try await manager.drop(drag)
        #expect(await replica.batches == batches + 1)
        let after = try await manager.dayPage(on: day)
        if target.id == carried.id { #expect(after.prefix(3).map(\.id) == visibleIDs + [carried.id]) }
        #expect(after.filter { blockIDs.contains($0.id) }.map(\.id) == visibleIDs)
        #expect(after.filter { !blockIDs.contains($0.id) }.map(\.id) == before.filter { !blockIDs.contains($0.id) }.map(\.id))
        #expect(after.contains { $0.id == history.id && $0.status == "completed" && $0.scheduled(calendar: calendar) == history.scheduled(calendar: calendar) })
        for original in [first, second] {
            let saved = try await manager.task(id: original.id)
            #expect(saved.scheduled(calendar: calendar) == target.plannerDate(calendar: calendar))
            for key in ["due", "entry", "opaque", "project"] { #expect(saved.attributes[key] == original.attributes[key]) }
        }
    }
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: blockIDs, context: .day(day), calendar: calendar)
    drag.cross(untimed.id)
    _ = try await manager.drop(drag)
    for id in blockIDs { #expect(try await manager.task(id: id).scheduled(calendar: calendar) == TaskScheduledDate(date: day, hasTime: false)) }
    let allDay = CalendarEventSnapshot(calendarID: "work", eventID: "all-day", title: "All day", calendarTitle: "Work", start: day, end: day.addingTimeInterval(86400), isAllDay: true)
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [first.id, second.id], context: .day(day), calendar: calendar)
    let beforeEvent = try await manager.tasks()
    drag.cross(event)
    #expect(drag.lastCrossedEventID == event.id)
    #expect(drag.tasks.filter { drag.ids.contains($0.id) }.allSatisfy { $0.scheduled(calendar: calendar) == .init(date: event.start, hasTime: true) })
    drag.cross(allDay)
    #expect(drag.lastCrossedEventID == event.id)
    drag.cross(carried.id)
    #expect(drag.lastCrossedEventID == nil && drag.lastCrossedID == carried.id)
    drag.cross(event)
    #expect(drag.lastCrossedID == nil && drag.lastCrossedEventID == event.id)
    #expect(try await manager.tasks() == beforeEvent)
    let batches = await replica.batches
    _ = try await manager.drop(drag)
    #expect(await replica.batches == batches + 1)
    #expect(try await manager.dayPage(on: day).filter { $0.scheduled(calendar: calendar) == .init(date: event.start, hasTime: true) }.map(\.id) == drag.ids)
    #expect(try await manager.task(id: first.id).scheduled(calendar: calendar) == .init(date: event.start, hasTime: true))
    #expect(try await manager.task(id: first.id).deadline == first.deadline)
    let projectBefore = try await manager.tasks(query: .unfinished, project: .project("Work"))
    drag = try TaskDragSession(tasks: projectBefore, ids: blockIDs, context: .project("Work"), calendar: calendar)
    let projectTarget = try #require(projectBefore.first { !blockIDs.contains($0.id) })
    drag.cross(event)
    #expect(drag.lastCrossedEventID == nil)
    drag.cross(projectTarget.id)
    _ = try await manager.drop(drag)
    for original in projectBefore {
        #expect(try await manager.task(id: original.id).scheduled(calendar: calendar) == original.scheduled(calendar: calendar))
    }
    #expect(try await manager.tasks(query: .unfinished, project: .project("Work")).map(\.id) == drag.tasks.map(\.id))
    let beforeFailure = try await manager.tasks()
    var stale = try TaskDragSession(tasks: beforeFailure, ids: [first.id], context: .project("Work"), calendar: calendar)
    stale.cross(second.id)
    _ = try await replica.updateAtomically([TaskAtomicUpdate(id: second.id, expected: try await manager.task(id: second.id).attributes, changes: ["opaque": "external change"])])
    let originals = try await manager.tasks()
    await #expect(throws: (any Error).self) { try await manager.drop(stale) }
    #expect(try await manager.tasks() == originals)
    #expect(originals != beforeFailure)
}

@Test func incomingSchedulingAppendsWithinIntentGroupsAndStorageFailureRetainsOriginals() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1792108800)
    let ids = (1...6).map { UUID(uuidString: String(format: "A1061000-0000-0000-0000-%012d", $0))! }
    let records = ids.enumerated().map { index, id in
        TaskRecord(id: id, attributes: ["status": "pending", "description": "Task \(index)", "scheduled": index < 2 ? "1792108800" : "1792026000", "due": "1792400000", "opaque": "retain", "entry": "1"])
    }
    let replica = OccurrenceReplica(records: records, allowsSingleWrites: true)
    let manager = TaskManager(replica: replica, now: { day }, calendar: calendar)
    let timedFirst = try await replica.create(id: UUID(), attributes: ["status": "pending", "scheduled": "1792198800", "entry": "200"])
    let timedSecond = try await replica.create(id: UUID(), attributes: ["status": "pending", "scheduled": "1792198800", "entry": "100"])
    let editorIncoming = try await replica.create(id: UUID(), attributes: ["status": "pending", "entry": "300", "due": "1792400000", "opaque": "keep editor"])
    _ = try await manager.update(id: editorIncoming.id, changes: ["scheduled": "1792198800"])
    #expect(try await manager.dayPage(on: day.addingTimeInterval(86400)).map(\.id) == [timedFirst.id, timedSecond.id, editorIncoming.id])
    #expect(try await manager.task(id: editorIncoming.id).attributes["due"] == "1792400000")
    #expect(try await manager.task(id: editorIncoming.id).attributes["opaque"] == "keep editor")
    var capture = TaskRowDraft(capturing: .day(day), calendar: calendar)
    capture.taskDraft.description = "Day capture"
    let capturing = TaskManager(replica: replica, now: { day.addingTimeInterval(3600) }, calendar: calendar)
    let captured = try await capturing.create(capture.creationDraft(at: day))
    let afterCapture = try await manager.dayPage(on: day).map(\.id)
    #expect(afterCapture == [ids[2], ids[3], ids[4], ids[5], ids[0], ids[1], captured.id])
    var row = TaskRowDraft(task: records[4])
    row.taskDraft.setScheduled(.init(date: day, hasTime: false))
    _ = try await manager.updateRow(row)
    let afterEditor = try await manager.dayPage(on: day).map(\.id)
    #expect(afterEditor == [ids[2], ids[3], ids[5], ids[0], ids[1], captured.id, ids[4]])
    _ = try await manager.update(id: ids[4], changes: ["scheduled": "1792026000"])
    _ = try await manager.update(id: captured.id, changes: ["scheduled": nil])
    var drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [ids[1]], context: .day(day), calendar: calendar)
    drag.cross(ids[0])
    _ = try await manager.drop(drag)
    _ = try await manager.schedule(ids: [ids[3], ids[2]], change: .intent(.init(date: day, hasTime: false)))
    #expect(try await manager.dayPage(on: day).suffix(4).map(\.id) == [ids[1], ids[0], ids[3], ids[2]])
    _ = try await manager.schedule(ids: [ids[0]], change: .intent(.init(date: day.addingTimeInterval(3600), hasTime: true)))
    _ = try await manager.schedule(ids: [ids[5], ids[4]], change: .intent(.init(date: day.addingTimeInterval(3600), hasTime: true)))
    #expect(try await manager.dayPage(on: day).map(\.id) == [ids[1], ids[3], ids[2], ids[0], ids[5], ids[4]])
    _ = try await manager.update(id: captured.id, changes: ["scheduled": "1792112400"])
    #expect(try await manager.dayPage(on: day).map(\.id) == [ids[1], ids[3], ids[2], ids[0], ids[5], ids[4], captured.id])
    var titleEdit = TaskRowDraft(task: try await manager.task(id: ids[0]))
    titleEdit.taskDraft.description = "Same group title edit"
    _ = try await manager.updateRow(titleEdit)
    #expect(try await manager.dayPage(on: day).map(\.id) == [ids[1], ids[3], ids[2], ids[0], ids[5], ids[4], captured.id])
    let original = try await manager.tasks()
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.schedule(ids: [ids[1], ids[3]], change: .intent(.init(date: day, hasTime: true))) }
    #expect(try await manager.tasks() == original)
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.create(capture.creationDraft(at: day)) }
    #expect(try await manager.tasks() == original)
    var failedRow = TaskRowDraft(task: try await manager.task(id: ids[1]))
    failedRow.taskDraft.setScheduled(.init(date: day.addingTimeInterval(3600), hasTime: true))
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.updateRow(failedRow) }
    #expect(try await manager.tasks() == original)
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: day), ids: [ids[1], ids[3]], context: .day(day), calendar: calendar)
    drag.cross(ids[0])
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.drop(drag) }
    #expect(try await manager.tasks() == original)
    for task in original where ids.contains(task.id) {
        #expect(task.attributes["due"] == "1792400000")
        #expect(task.attributes["entry"] == "1")
        #expect(task.attributes["opaque"] == "retain")
    }
}

@Test func calendarSchedulingPreservesMixedPlannerIntentAndMembershipInOneBatch() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1792108800)
    func task(_ index: Int, _ intent: TaskScheduledDate?, due: String? = nil, project: String? = nil) -> TaskRecord {
        var draft = TaskDraft(description: "Calendar task \(index)", attributes: ["status": "pending", "entry": "1", "opaque": "retain"])
        draft.setScheduled(intent)
        draft.attributes["due"] = due
        draft.attributes["project"] = project
        return TaskRecord(id: UUID(uuidString: String(format: "A1070000-0000-0000-0000-%012d", index))!, attributes: draft.attributes)
    }
    let originals = [
        task(1, .init(date: day, hasTime: false)),
        task(2, .init(date: day, hasTime: true), due: "1792238400", project: "Work"),
        task(3, .init(date: day.addingTimeInterval(36000), hasTime: true)),
        task(4, nil, due: "1792159200"),
        task(5, nil, due: "1792108800"),
        task(6, nil)
    ]
    let replica = OccurrenceReplica(records: originals)
    let manager = TaskManager(replica: replica, now: { day }, calendar: calendar)
    let ids = originals.map(\.id)
    let destination = day.addingTimeInterval(86400)
    _ = try await manager.schedule(ids: ids, change: .day(destination))
    let expected: [TimeInterval] = [1792195200, 1792195200, 1792231200, 1792245600, 1792195200, 1792195200]
    for (index, original) in originals.enumerated() {
        let saved = try await manager.task(id: original.id)
        #expect(saved.scheduled(calendar: calendar) == TaskScheduledDate(date: Date(timeIntervalSince1970: expected[index]), hasTime: [false, true, true, true, false, false][index]))
        for key in ["due", "project", "entry", "opaque"] { #expect(saved.attributes[key] == original.attributes[key]) }
    }
    #expect(try await manager.dayPage(on: day).isEmpty)
    #expect(try await manager.tasks(query: .inbox).isEmpty)
    #expect(try await manager.tasks(query: .unfinished, project: .project("Work")).map(\.id) == [ids[1]])
    #expect(try await manager.dayPage(on: destination).map(\.id) == [ids[0], ids[4], ids[5], ids[1], ids[2], ids[3]])
    #expect(await replica.batches == 1)
    let beforeFailure = try await manager.tasks()
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.schedule(ids: ids, change: .day(day)) }
    #expect(try await manager.tasks() == beforeFailure)
}
