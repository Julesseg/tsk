import SwiftUI
import TskCore

extension WorkspaceView {
    @MainActor func title(in store: TaskStore) -> String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .unfinished: "All"
        case .completed: "Done"
        case .projects: "Projects"
        case .custom(let id): store.savedViews.first(where: { $0.id == id })?.name ?? "Custom view"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .unfinished: "checklist"
        case .completed: "checkmark.circle"
        case .projects: "folder"
        case .custom: "line.3.horizontal.decrease"
        }
    }
}
