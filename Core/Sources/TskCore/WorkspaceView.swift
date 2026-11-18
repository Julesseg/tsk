public enum WorkspaceView: Equatable, Sendable {
    case today, inbox, projects

    public var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .projects: "Projects"
        }
    }

    public var query: TaskQuery {
        switch self {
        case .today: .today
        case .inbox: .inbox
        case .projects: .unfinished
        }
    }
}
