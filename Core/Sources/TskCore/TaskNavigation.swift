import Foundation

public enum TaskNavigationView: Equatable, Sendable {
    case today, inbox, unfinished, done, projects, project(String)

    public static let predefined: [Self] = [.today, .inbox, .projects]

    public var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .unfinished: "All unfinished"
        case .done: "Done"
        case .projects: "Projects"
        case .project(let name): name
        }
    }

    public var url: URL {
        var components = URLComponents(string: "tsk://open-view")!
        let items: [URLQueryItem]
        switch self {
        case .project(let name): items = [.init(name: "view", value: "project"), .init(name: "project", value: name)]
        default: items = [.init(name: "view", value: id)]
        }
        components.queryItems = items
        return components.url!
    }

    public var id: String {
        switch self {
        case .today: "today"
        case .inbox: "inbox"
        case .unfinished: "unfinished"
        case .done: "done"
        case .projects: "projects"
        case .project(let name): "project:" + Data(name.utf8).base64EncodedString()
        }
    }

    public var workspace: WorkspaceView {
        switch self {
        case .today: .today
        case .inbox, .unfinished, .done, .project: .inbox
        case .projects: .projects
        }
    }

    public var query: TaskQuery {
        switch self {
        case .unfinished, .project: .unfinished
        case .done: .completed
        default: workspace.query
        }
    }
}

public struct TaskNavigationDestination: Sendable {
    public let view: TaskNavigationView
    public let title: String
    public let snapshot: TaskViewSnapshot
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
        return TaskNavigationDestination(view: view, title: destination.title, snapshot: destination.snapshot, task: current)
    }

    func navigationDestination(view: TaskNavigationView) async throws -> TaskNavigationDestination {
        let snapshot: TaskViewSnapshot
        let title: String
        switch view {
        case .project(let name):
            let records = try await tasks()
            guard !name.isEmpty, TaskProjectSelection.names(in: records).contains(where: { $0.matchesBytes(name) }) else {
                throw TaskActionError.navigationFailed("This project no longer exists: \(name)")
            }
            title = name
            snapshot = try await viewSnapshot(query: .unfinished, project: .project(name))
        default:
            title = view.title
            snapshot = try await viewSnapshot(query: view.query)
        }
        return TaskNavigationDestination(view: view, title: title, snapshot: snapshot, task: nil)
    }
}

public extension TaskRecord {
    var canOpenInWorkspace: Bool { canEdit || status == "completed" }
}
