import Foundation
import Testing
import TskCore
import TskNative

@Test func workspaceViewPreferencesPersistSeparatelyFromCustomFilters() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalWorkspaceViewStore(directory: directory)
    let id = UUID()
    var views = try store.load(customIDs: [id])
    try views.deactivate(.completed)
    try views.activate(.custom(id))
    views.moveActive(from: IndexSet(integer: 4), to: 0)
    try store.save(views)
    #expect(try LocalWorkspaceViewStore(directory: directory).load(customIDs: [id]) == views)
    #expect(try store.load(customIDs: []).active == views.active.filter { $0 != .custom(id) })
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("saved-task-views.json").path))
}
