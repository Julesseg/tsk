import Foundation
import Testing
@testable import TskCore

@Test func workspaceViewsKeepFiveTabsAndRequireOne() throws {
    var views = WorkspaceViews(customIDs: [])
    #expect(views.active == [.unfinished, .today, .upcoming, .projects, .completed])
    let id = UUID()
    views.reconcile(customIDs: [id])
    #expect(throws: WorkspaceViewsError.limitReached) { try views.activate(.custom(id)) }
    try views.deactivate(.completed)
    try views.activate(.custom(id))
    views.moveActive(from: IndexSet(integer: 4), to: 0)
    #expect(views.active.first == .custom(id))
    for view in views.active.dropFirst() { try views.deactivate(view) }
    #expect(throws: WorkspaceViewsError.lastActiveView) { try views.deactivate(.custom(id)) }
}

@Test func workspaceViewsRestoreOrderAndRepairDeletedCustomViews() throws {
    let first = UUID(), second = UUID()
    var views = WorkspaceViews(customIDs: [first, second])
    try views.deactivate(.unfinished)
    try views.activate(.custom(first))
    views.moveActive(from: IndexSet(integer: 4), to: 0)
    views.moveInactive(from: IndexSet(integer: 2), to: 0)
    let restored = try JSONDecoder().decode(WorkspaceViews.self, from: JSONEncoder().encode(views))
    #expect(restored == views)
    views.reconcile(customIDs: [second])
    #expect(!views.active.contains(.custom(first)))
    #expect(views.inactive.contains(.custom(second)))
    #expect(Set(views.active + views.inactive).count == 6)
    #expect(views.active.first == .today)
}

@Test func workspaceViewsRecoverWhenOnlyActiveCustomViewIsDeleted() throws {
    let id = UUID()
    var views = WorkspaceViews(customIDs: [id])
    try views.deactivate(.completed)
    try views.activate(.custom(id))
    for view in views.active.filter({ $0 != .custom(id) }) { try views.deactivate(view) }
    views.reconcile(customIDs: [])
    #expect(views.active.count == 1)
    #expect(Set(views.active + views.inactive) == Set(WorkspaceView.defaults))
    #expect(throws: WorkspaceViewsError.unavailableView) { try views.activate(.custom(UUID())) }
}
