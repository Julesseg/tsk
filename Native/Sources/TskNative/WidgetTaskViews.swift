#if canImport(AppIntents) && canImport(WidgetKit)
import AppIntents
import Foundation
import TskCore
import WidgetKit

@available(iOS 17, macOS 14, *)
public struct WidgetTaskViewEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task view"
    public static let defaultQuery = WidgetTaskViewQuery()
    public let id: String
    public let name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(_ view: RegisteredTaskView) { id = view.id; name = view.name }
    public init(id: String, name: String) { self.id = id; self.name = name }
    public static let today = WidgetTaskViewEntity(.init(reference: .query(.today), name: "Today"))
}

@available(iOS 17, macOS 14, *)
public struct WidgetTaskViewQuery: EntityStringQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [WidgetTaskViewEntity] {
        let views = try await suggestedEntities()
        return identifiers.map { id in views.first(where: { $0.id == id }) ?? WidgetTaskViewEntity(id: id, name: "Unavailable view") }
    }
    public func entities(matching string: String) async throws -> [WidgetTaskViewEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    public func defaultResult() async -> WidgetTaskViewEntity? { .today }
    public func suggestedEntities() async throws -> [WidgetTaskViewEntity] {
        let directory = try TaskChampionSession.participantDirectory()
        let manager = try await TaskChampionSession.open(directory: directory)
        return try await manager.registeredViews().map(WidgetTaskViewEntity.init)
    }
}

@available(iOS 17, macOS 14, *)
public struct TaskWidgetConfiguration: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Task view"
    public static let description = IntentDescription("Show Today or another registered tsk view, including your device-local saved filters.")
    @Parameter(title: "View") public var view: WidgetTaskViewEntity?
    public init() { view = .today }
    public static var parameterSummary: some ParameterSummary { Summary("Show \(\.$view)") }
}
#endif
