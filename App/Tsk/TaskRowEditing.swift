import Foundation
import Observation
import TskCore

@MainActor @Observable
final class TaskRowEditing {
    let rowID: String
    let context: TaskCompletionFeedback.Context
    let tasks: [TaskRecord]
    let upcomingDays: [UpcomingDay]
    var draft: TaskRowDraft
    var parameter: TaskDateParameter?
    var error: String?
    var isExpanded = true
    var isSaving = false
    var bounds = CGRect.zero

    init(task: TaskRecord, rowID: String, context: TaskCompletionFeedback.Context, tasks: [TaskRecord], now: Date) {
        self.rowID = rowID
        self.context = context
        self.tasks = tasks
        upcomingDays = UpcomingDay.groups(tasks: tasks, at: now)
        draft = TaskRowDraft(task: task)
    }
}

enum TaskDateParameter: String, Identifiable, CaseIterable {
    case planned = "Planned day", deadline = "Deadline", waiting = "Waiting date"
    var id: String { rawValue }
    var attribute: String {
        switch self { case .planned: "scheduled"; case .deadline: "due"; case .waiting: "wait" }
    }
    var symbol: String {
        switch self { case .planned: "calendar"; case .deadline: "flag"; case .waiting: "pause.circle" }
    }
    func date(in draft: TaskDraft) -> Date? {
        switch self { case .planned: draft.plannedDate; case .deadline: draft.deadline; case .waiting: draft.waitUntil }
    }
    func setDate(_ date: Date, in draft: inout TaskRowDraft) {
        switch self {
        case .planned: draft.choosePlannedDay(date)
        case .deadline: draft.taskDraft.deadline = date
        case .waiting: draft.taskDraft.waitUntil = date
        }
    }
    var identifier: String {
        switch self { case .planned: "planned-day"; case .deadline: "deadline"; case .waiting: "waiting-date" }
    }
}

extension UpcomingTaskEntry {
    var rowIdentifier: String { "upcoming-\(role.rawValue)-\(Int(date.timeIntervalSince1970))-\(task.id.uuidString)" }
}
