import Foundation
import Observation
import SwiftUI
import TskCore

@MainActor @Observable
final class TaskRowEditing {
    let rowID: String
    let context: TaskCompletionFeedback.Context
    let tasks: [TaskRecord]
    let upcomingDays: [UpcomingDay]
    let referenceDate: Date
    var draft: TaskRowDraft
    var parameter: TaskRowParameter?
    var savedTask: TaskRecord?
    var error: String?
    var isExpanded = false
    var isSaving = false
    var viewport = CGRect.zero
    private(set) var bounds = CGRect.zero
    private(set) var visibilityBounds = CGRect.zero
    private(set) var isAnimating = false
    var revealProgress: CGFloat = 0
    var focusInset: CGFloat = 12
    @ObservationIgnored private var motion: TaskRowMotion?

    init(task: TaskRecord, rowID: String, context: TaskCompletionFeedback.Context, tasks: [TaskRecord], now: Date) {
        self.rowID = rowID
        self.context = context
        self.tasks = tasks
        referenceDate = now
        upcomingDays = UpcomingDay.groups(tasks: tasks, at: now)
        draft = TaskRowDraft(task: task)
    }

    func setExpanded(_ expanded: Bool, reduceMotion: Bool) async {
        motion?.cancel()
        motion = nil
        isAnimating = true
        isExpanded = expanded
        let target: CGFloat = expanded ? 1 : 0
        let initial = revealProgress
        let duration = (expanded ? 0.18 : 0.14) * Double(abs(target - initial))
        guard !reduceMotion, duration > 0 else {
            revealProgress = target
            visibilityBounds = bounds
            isAnimating = false
            return
        }
        let animation = TaskRowMotion(duration: duration) { [weak self] eased in
            guard let self else { return }
            withTransaction(Transaction(animation: nil)) {
                revealProgress = initial + (target - initial) * eased
            }
        }
        motion = animation
        await animation.run()
        if motion === animation {
            revealProgress = target
            motion = nil
            visibilityBounds = bounds
            isAnimating = false
        }
    }

    func measure(_ bounds: CGRect) {
        self.bounds = bounds
        if !isAnimating { visibilityBounds = bounds }
    }
}

enum TaskRowParameter: String, Identifiable, CaseIterable {
    case project, scheduled, deadline, waiting, priority
    var id: String { rawValue }
    var title: String {
        switch self {
        case .project: "Project"
        case .scheduled: "Scheduled"
        case .deadline: "Deadline"
        case .waiting: "Waiting date"
        case .priority: "Priority"
        }
    }
    var attribute: String {
        switch self { case .deadline: "due"; case .waiting: "wait"; default: rawValue }
    }
    var symbol: String {
        switch self {
        case .project: "folder"
        case .scheduled: "calendar"
        case .deadline: "flag"
        case .waiting: "pause.circle"
        case .priority: "exclamationmark"
        }
    }
    func date(in draft: TaskDraft) -> Date? {
        switch self {
        case .scheduled: draft.plannedDate
        case .deadline: draft.deadline
        case .waiting: draft.waitUntil
        default: nil
        }
    }
    func setDate(_ date: Date, in draft: inout TaskRowDraft) {
        switch self {
        case .scheduled: draft.choosePlannedDay(date)
        case .deadline: draft.taskDraft.deadline = date
        case .waiting: draft.taskDraft.waitUntil = date
        default: break
        }
    }
    func value(in draft: TaskDraft) -> String? {
        if let date = date(in: draft) {
            return date.formatted(date: .abbreviated, time: self == .scheduled ? .omitted : .shortened)
        }
        guard let raw = draft.attributes[attribute], !raw.isEmpty else { return nil }
        switch self {
        case .project: return raw
        case .priority: return Self.priorityTitle(raw)
        default: return "Unrecognized date"
        }
    }
    static func priorityTitle(_ value: String) -> String {
        ["": "None", "L": "Low", "M": "Medium", "H": "High"][value] ?? value
    }
    var identifier: String { self == .waiting ? "waiting-date" : rawValue }
}

extension UpcomingTaskEntry {
    var rowIdentifier: String { "upcoming-\(role.rawValue)-\(Int(date.timeIntervalSince1970))-\(task.id.uuidString)" }
}
