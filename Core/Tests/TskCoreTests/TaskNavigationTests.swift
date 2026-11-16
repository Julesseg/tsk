import Foundation
import Testing
@testable import TskCore

@Test func openViewURLsUseStrictNamedArgumentsAndStableSavedIdentity() throws {
    let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
    let views: [TaskNavigationView] = [.today, .upcoming, .unfinished, .done, .projects, .project("Café & +"), .saved(id)]
    for view in views {
        #expect(try TaskActionURL(url: view.url) == .openView(view))
    }
    for query in ["", "view=all", "view=Today", "view=today&project=Home", "view=project", "view=project&project=", "view=saved&id=1", "view=saved&name=Old", "view=done&view=today", "view=projects&filter=+PENDING"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://open-view?" + query))) }
    }
    #expect(try TaskActionURL(url: #require(URL(string: "tsk://open-task?id=\(id)&x-success=caller%3A%2F%2Fdone"))) == .openTask(id))
}

@Test func navigationResolvesCurrentTaskAndContainingListAndRejectsDeletedIdentity() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let original = try await manager.create(TaskDraft(description: "Original"))
    _ = try await manager.update(id: original.id, changes: ["description": "Current"])
    let opened = try await manager.navigationDestination(taskID: original.id)
    #expect(opened.task?.description == "Current")
    #expect(opened.view == .unfinished)
    #expect(opened.snapshot.listTasks.map(\.id) == [original.id])
    _ = try await manager.complete(id: original.id)
    let completed = try await manager.navigationDestination(taskID: original.id)
    #expect(completed.view == .done)
    #expect(completed.task?.status == "completed")
    _ = try await replica.update(id: original.id, changes: ["status": "deleted"])
    await #expect(throws: TaskManagementError.taskNotFound(original.id)) { try await manager.navigationDestination(taskID: original.id) }
    let missing = UUID()
    await #expect(throws: TaskManagementError.taskNotFound(missing)) { try await manager.navigationDestination(taskID: missing) }
}

@Test func navigationUsesExactProjectAndNeverCreatesViews() async throws {
    let manager = TaskManager(replica: TestReplica())
    _ = try await manager.create(TaskDraft(description: "Travel", attributes: ["project": "Work.Travel"]))
    let opened = try await manager.navigationDestination(view: .project("Work.Travel"))
    #expect(opened.snapshot.listTasks.map(\.description) == ["Travel"])
    await #expect(throws: (any Error).self) { try await manager.navigationDestination(view: .project("Work")) }
    for view: TaskNavigationView in [.today, .upcoming, .unfinished, .done, .projects] {
        #expect(try await manager.navigationDestination(view: view).view == view)
    }
}

@Test func navigationCallbackAcknowledgesDestinationWithoutClaimingTaskCreation() async throws {
    let manager = TaskManager(replica: TestReplica())
    let destination = try await manager.navigationDestination(view: .done)
    let callbacks = try TaskActionCallbacks(url: #require(URL(string: "tsk://open-view?view=done&x-success=caller%3A%2F%2Fdone")))
    let url = try #require(try callbacks.navigationURL(for: destination))
    let json = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "result" }?.value)
    let result = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(result["success"] as? Bool == true)
    #expect(result["navigated"] as? Bool == true)
    #expect(result["savedLocally"] as? Bool == false)
    #expect(result["title"] as? String == "Done")
    #expect(result["view"] as? String == "tsk://open-view?view=done")
}

@Test func completedOccurrenceCanOpenWithoutAcquiringMutationRights() async throws {
    let replica = TestReplica()
    let id = UUID()
    _ = try await replica.create(id: id, attributes: ["description": "Completed occurrence", "status": "completed", "parent": UUID().uuidString, "imask": "0", "due": "2000000000"])
    let manager = TaskManager(replica: replica)
    let destination = try await manager.navigationDestination(taskID: id)
    #expect(destination.view == .done)
    #expect(destination.task?.canEdit == false)
    #expect(destination.task?.canOpenInWorkspace == true)
    #expect(destination.snapshot.listTasks.map(\.id) == [id])
}
