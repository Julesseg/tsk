import SwiftUI
import TskCore

struct TaskAvailabilityView: View {
    let task: TaskRecord
    let store: TaskStore
    var isDetail = false

    var body: some View {
        TimelineView(.explicit([Date(), task.waitUntil].compactMap { $0 }.sorted())) { _ in
            let availability = store.availability(for: task, at: Date())
            if !availability.reasons.isEmpty || !availability.diagnostics.isEmpty {
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
            case .blocked(let prerequisites):
                Text("Blocked by \(prerequisites.map(\.description).joined(separator: ", "))")
                    .accessibilityIdentifier("task-blocked-reason-\(task.id.uuidString)")
            }
        }
        ForEach(availability.diagnostics) { link in
            Text("\(link.issue?.message ?? "Dependency issue"): \(link.reference.isEmpty ? "<empty reference>" : link.reference)")
                .accessibilityIdentifier("task-dependency-diagnostic-\(task.id.uuidString)-\(link.id.base64EncodedString())")
        }
    }
}
