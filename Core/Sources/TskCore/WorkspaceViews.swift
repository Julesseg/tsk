import Foundation

public enum WorkspaceView: Hashable, Codable, Identifiable, Sendable {
    case today, upcoming, unfinished, completed, projects, custom(UUID)

    public static let defaults: [Self] = [.unfinished, .today, .upcoming, .projects, .completed]

    public var id: String {
        switch self {
        case .today: "today"
        case .upcoming: "upcoming"
        case .unfinished: "unfinished"
        case .completed: "completed"
        case .projects: "projects"
        case .custom(let id): "custom-" + id.uuidString
        }
    }

    public var query: TaskQuery? {
        switch self {
        case .today: .today
        case .upcoming: .upcoming
        case .unfinished: .unfinished
        case .completed: .completed
        case .projects, .custom: nil
        }
    }
}

public enum WorkspaceViewsError: Error, LocalizedError, Equatable {
    case limitReached, lastActiveView, unavailableView

    public var errorDescription: String? {
        switch self {
        case .limitReached: "You can show up to five tabs. Remove an active view before adding another."
        case .lastActiveView: "Keep at least one active view."
        case .unavailableView: "This view is no longer available."
        }
    }
}

public struct WorkspaceViews: Codable, Equatable, Sendable {
    public static let maximumActive = 5
    public private(set) var active: [WorkspaceView]
    public private(set) var inactive: [WorkspaceView]

    public init(customIDs: [UUID]) {
        active = WorkspaceView.defaults
        inactive = []
        reconcile(customIDs: customIDs)
    }

    public mutating func reconcile(customIDs: [UUID]) {
        let catalog = WorkspaceView.defaults + customIDs.map(WorkspaceView.custom)
        var seen: Set<WorkspaceView> = []
        active = Array(active.filter { catalog.contains($0) && seen.insert($0).inserted }.prefix(Self.maximumActive))
        seen = Set(active)
        inactive = (inactive + catalog).filter { catalog.contains($0) && seen.insert($0).inserted }
        if active.isEmpty, !inactive.isEmpty { active = [inactive.removeFirst()] }
    }

    public mutating func activate(_ view: WorkspaceView) throws {
        guard let index = inactive.firstIndex(of: view) else { throw WorkspaceViewsError.unavailableView }
        guard active.count < Self.maximumActive else { throw WorkspaceViewsError.limitReached }
        inactive.remove(at: index)
        active.append(view)
    }

    public mutating func deactivate(_ view: WorkspaceView) throws {
        guard let index = active.firstIndex(of: view) else { throw WorkspaceViewsError.unavailableView }
        guard active.count > 1 else { throw WorkspaceViewsError.lastActiveView }
        active.remove(at: index)
        inactive.append(view)
    }

    public mutating func moveActive(from offsets: IndexSet, to destination: Int) {
        active = reordered(active, from: offsets, to: destination)
    }

    public mutating func moveInactive(from offsets: IndexSet, to destination: Int) {
        inactive = reordered(inactive, from: offsets, to: destination)
    }

    private func reordered(_ views: [WorkspaceView], from offsets: IndexSet, to destination: Int) -> [WorkspaceView] {
        let selected = views.enumerated().filter { offsets.contains($0.offset) }.map(\.element)
        var remaining = views.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = min(remaining.count, max(0, destination - offsets.filter { $0 < destination }.count))
        remaining.insert(contentsOf: selected, at: insertion)
        return remaining
    }
}
