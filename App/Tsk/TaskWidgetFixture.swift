#if DEBUG
import Foundation
import TskCore
import TskNative
import WidgetKit

func installWidgetFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["TSK_TEST_WIDGET_FIXTURE"] else { return }
    guard environment["TSK_TEST_REPLICA_NAME"] == nil, UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
    let directory = try TaskChampionSession.directory()
    let manager = try await TaskChampionSession.open(directory: directory)
    let todayName = "Widget Today " + token
    let customName = "Widget Custom " + token
    var records = try await manager.tasks()
    for (name, attributes) in [(todayName, TaskAttributes([("scheduled", String(Int(Date().timeIntervalSince1970))), ("foreign_é", "composed"), ("foreign_e\u{301}", "decomposed")])), (customName, TaskAttributes())] {
        if !records.contains(where: { $0.description == name }) {
            records.append(try await manager.create(TaskDraft(description: name, attributes: attributes)))
        }
    }
    let viewName = "Widget saved " + token
    let views = try await manager.savedViews()
    if environment["TSK_TEST_WIDGET_DELETE_VIEW"] == "1" {
        if let view = views.first(where: { $0.name == viewName }) { try await manager.deleteView(id: view.id) }
    } else if !views.contains(where: { $0.name == viewName }) {
        _ = try await manager.saveView(name: viewName, expression: "description.is:\"\(customName)\"")
    }
    records = try await manager.tasks()
    let proof = records.filter { $0.description == todayName || $0.description == customName }
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("widgets-fixture-\(token).json")
    try JSONEncoder().encode(proof).write(to: output, options: .atomic)
    WidgetCenter.shared.reloadTimelines(ofKind: "tsk.tasks")
}
#endif
