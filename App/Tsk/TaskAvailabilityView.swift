import SwiftUI
import TskCore

struct TaskAvailabilityView: View {
    let task: TaskRecord
    let store: TaskStore
    var isDetail = false

    var body: some View {
        TimelineView(.explicit([Date(), task.waitUntil].compactMap { $0 }.sorted())) { _ in
            let availability = store.availability(for: task, at: Date())
            if !availability.reasons.isEmpty {
                if isDetail {
                    Section("Availability") { reasons(availability) }
                } else {
                    reasons(availability).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func reasons(_ availability: TaskAvailability) -> some View {
        ForEach(Array(availability.reasons.enumerated()), id: \.offset) { item in
            switch item.element {
            case .waiting(let until):
                Text("Waiting until \(until, format: .dateTime.day().month().year().hour().minute())")
                    .accessibilityIdentifier("task-waiting-reason-\(task.id.uuidString)")
            }
        }
    }
}
