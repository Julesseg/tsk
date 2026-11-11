#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore

@available(iOS 16, macOS 13, *)
public struct IntentTaskViewEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task view"
    public static let defaultQuery = IntentTaskViewQuery()
    public let id: String
    public let name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    public init(view: TaskNavigationView, name: String) {
        id = view.url.absoluteString
        self.name = name
    }

    public var view: TaskNavigationView {
        get throws {
            guard let url = URL(string: id), case .openView(let view) = try TaskActionURL(url: url) else {
                throw TaskActionError.invalidInput("This task view is unavailable.")
            }
            return view
        }
    }
}

@available(iOS 16, macOS 13, *)
public struct IntentTaskViewQuery: EntityStringQuery {
    private let directory: URL?
    public init() { directory = nil }
    public init(directory: URL) { self.directory = directory }

    public func entities(for identifiers: [String]) async throws -> [IntentTaskViewEntity] {
        let available = try await suggestedEntities()
        return identifiers.compactMap { id in available.first { $0.id == id } }
    }

    public func entities(matching string: String) async throws -> [IntentTaskViewEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    public func suggestedEntities() async throws -> [IntentTaskViewEntity] {
        let manager = try await IntentTaskSession.open(directory: directory)
        let builtins = TaskNavigationView.predefined.map { IntentTaskViewEntity(view: $0, name: $0.title) }
        let projects = try await manager.projects().map { IntentTaskViewEntity(view: .project($0), name: $0) }
        let saved = try await manager.savedViews().map { IntentTaskViewEntity(view: .saved($0.id), name: $0.name) }
        return builtins + projects + saved
    }
}

@available(iOS 16, macOS 13, *)
public struct OpenTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Task"
    public static let description = IntentDescription("Open the current saved task in its containing list in tsk. Current valid edits are saved before navigation.")
    public static let openAppWhenRun = true
    @Parameter(title: "Task") public var task: IntentTaskEntity
    private var navigation: ForegroundTaskNavigation?
    public static var parameterSummary: some ParameterSummary { Summary("Open \(\.$task)") }
    public init() {}
    public init(task: IntentTaskEntity, navigation: ForegroundTaskNavigation? = nil) { self.task = task; self.navigation = navigation }

    @MainActor public func perform() async throws -> some IntentResult {
        try await (navigation ?? .shared).open(.openTask(task.id))
        return .result()
    }
}

@available(iOS 16, macOS 13, *)
public struct OpenTaskViewIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open View"
    public static let description = IntentDescription("Open an existing task view in tsk without changing favorites. Saved views keep their identity after renaming.")
    public static let openAppWhenRun = true
    @Parameter(title: "View") public var view: IntentTaskViewEntity
    private var navigation: ForegroundTaskNavigation?
    public static var parameterSummary: some ParameterSummary { Summary("Open \(\.$view)") }
    public init() {}
    public init(view: IntentTaskViewEntity, navigation: ForegroundTaskNavigation? = nil) { self.view = view; self.navigation = navigation }

    @MainActor public func perform() async throws -> some IntentResult {
        try await (navigation ?? .shared).open(.openView(view.view))
        return .result()
    }
}
#endif
