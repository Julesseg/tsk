import Foundation

public enum TaskNavigationView: Equatable, Sendable {
    case today, upcoming, unfinished, done, projects, project(String), saved(UUID)

    public static let predefined: [Self] = [.today, .upcoming, .unfinished, .done, .projects]

    public var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .unfinished: "All unfinished"
        case .done: "Done"
        case .projects: "Projects"
        case .project(let name): name
        case .saved: "Saved view"
        }
    }

    public var url: URL {
        var components = URLComponents(string: "tsk://open-view")!
        let items: [URLQueryItem]
        switch self {
        case .project(let name): items = [.init(name: "view", value: "project"), .init(name: "project", value: name)]
        case .saved(let id): items = [.init(name: "view", value: "saved"), .init(name: "id", value: id.uuidString)]
        default: items = [.init(name: "view", value: id)]
        }
        components.queryItems = items
        return components.url!
    }

    public var id: String {
        switch self {
        case .today: "today"
        case .upcoming: "upcoming"
        case .unfinished: "unfinished"
        case .done: "done"
        case .projects: "projects"
        case .project(let name): "project:" + Data(name.utf8).base64EncodedString()
        case .saved(let id): "saved:" + id.uuidString
        }
    }

    public var workspace: WorkspaceView {
        switch self {
        case .today: .today
        case .upcoming: .upcoming
        case .unfinished, .project: .unfinished
        case .done: .completed
        case .projects: .projects
        case .saved(let id): .custom(id)
        }
    }
}

public struct TaskNavigationDestination: Sendable {
    public let view: TaskNavigationView
    public let title: String
    public let snapshot: TaskViewSnapshot
    public let savedView: SavedTaskView?
    public let task: TaskRecord?
}

public extension TaskManager {
    func navigationDestination(taskID: UUID) async throws -> TaskNavigationDestination {
        let task = try await task(id: taskID)
        guard task.status != "deleted" else { throw TaskManagementError.taskNotFound(taskID) }
        guard task.canOpenInWorkspace else { throw TaskManagementError.unsupportedTaskKind }
        let view: TaskNavigationView = task.status == "completed" ? .done : .unfinished
        let destination = try await navigationDestination(view: view)
        guard let current = destination.snapshot.listTasks.first(where: { $0.id == taskID }), current.canOpenInWorkspace else {
            throw TaskManagementError.taskNotFound(taskID)
        }
        return TaskNavigationDestination(view: view, title: destination.title, snapshot: destination.snapshot, savedView: nil, task: current)
    }

    func navigationDestination(view: TaskNavigationView) async throws -> TaskNavigationDestination {
        let snapshot: TaskViewSnapshot
        let saved: SavedTaskView?
        let title: String
        switch view {
        case .saved(let id):
            guard let definition = try await savedViews().first(where: { $0.id == id }) else { throw TaskViewError.missingView(id) }
            saved = definition
            title = definition.name
            snapshot = try await viewSnapshot(reference: .custom(id))
        case .project(let name):
            let records = try await tasks()
            guard !name.isEmpty, TaskProjectSelection.names(in: records).contains(where: { $0.matchesBytes(name) }) else {
                throw TaskActionError.navigationFailed("This project no longer exists: \(name)")
            }
            saved = nil
            title = name
            snapshot = try await viewSnapshot(query: .unfinished, project: .project(name))
        default:
            saved = nil
            title = view.title
            snapshot = try await viewSnapshot(query: view.workspace.query ?? .unfinished)
        }
        return TaskNavigationDestination(view: view, title: title, snapshot: snapshot, savedView: saved, task: nil)
    }
}

public extension TaskRecord {
    var canOpenInWorkspace: Bool { canEdit || status == "completed" }
}
