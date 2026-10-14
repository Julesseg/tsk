import Foundation
import Testing
@testable import TskCore

@Test func dependencySelectionBlocksMatchingTodayTaskAndCompletionKeepsLinkMetadata() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) })
    let prerequisite = try await manager.create(TaskDraft(description: "Prerequisite outside Today", attributes: ["project": "Other"]))
    let dependent = try await manager.create(TaskDraft(description: "Planned dependent", attributes: ["scheduled": "1791928800", "due": "1792015200", "wait": "1792058400", "project": "Selected", "opaque": "retain"]))
    let linked = try await manager.addDependency(id: dependent.id, prerequisiteID: prerequisite.id)
    let reference = prerequisite.id.uuidString.lowercased()
    #expect(linked.id == dependent.id)
    #expect(linked.attributes["dep_\(reference)"] == "x")
    #expect(linked.attributes["depends"] == reference)
    #expect(linked.attributes["opaque"] == "retain")
    #expect(try await manager.tasks(query: .today, project: .project("Selected")).map(\.id) == [dependent.id])
    let availability = try await manager.availability(id: dependent.id)
    #expect(availability.isWaiting)
    #expect(availability.isBlocked)
    #expect(availability.reasons == [.waiting(until: Date(timeIntervalSince1970: 1792058400)), .blocked(by: [prerequisite])])
    _ = try await manager.complete(id: prerequisite.id)
    let unblocked = try await manager.availability(id: dependent.id)
    #expect(!unblocked.isBlocked)
    #expect(unblocked.isWaiting)
    #expect(try await manager.task(id: dependent.id).attributes["dep_\(reference)"] == "x")
    #expect(try await manager.task(id: dependent.id).attributes["depends"] == reference)
    #expect(try await manager.dependencyLinks(id: dependent.id).first?.task?.status == "completed")
}

@Test func dependencyMutationsRejectSelfMissingAndCyclesAndReconcileOnlyDedicatedChanges() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) })
    let first = try await manager.create(TaskDraft(description: "First", attributes: ["opaque": "retain"]))
    let second = try await manager.create(TaskDraft(description: "Second"))
    let third = try await manager.create(TaskDraft(description: "Third"))
    await #expect(throws: TaskManagementError.dependencySelfReference) {
        try await manager.addDependency(id: first.id, prerequisiteID: first.id)
    }
    let missing = UUID()
    await #expect(throws: TaskManagementError.taskNotFound(missing)) {
        try await manager.addDependency(id: first.id, prerequisiteID: missing)
    }
    let linked = try await manager.addDependency(id: first.id, prerequisiteID: second.id)
    #expect(try await manager.addDependency(id: first.id, prerequisiteID: second.id) == linked)
    _ = try await manager.addDependency(id: second.id, prerequisiteID: third.id)
    await #expect(throws: TaskManagementError.dependencyCycle) {
        try await manager.addDependency(id: third.id, prerequisiteID: first.id)
    }
    #expect(try await manager.task(id: third.id) == third)
    await #expect(throws: TaskManagementError.reservedAttribute("depends")) {
        try await manager.update(id: first.id, changes: ["depends": third.id.uuidString.lowercased()])
    }
    let key = "dep_\(third.id.uuidString.lowercased())"
    await #expect(throws: TaskManagementError.reservedAttribute(key)) {
        try await manager.update(id: first.id, changes: [key: "x"])
    }
    let removed = try await manager.removeDependency(id: first.id, reference: second.id.uuidString.lowercased())
    #expect(removed.dependencyReferences.isEmpty)
    #expect(removed.attributes["depends"] == nil)
    #expect(removed.attributes["opaque"] == "retain")
    #expect(try await manager.availability(id: first.id).isAvailable)
    await #expect(throws: TaskManagementError.dependencyReferenceNotFound("not a reference")) {
        try await manager.removeDependency(id: first.id, reference: "not a reference")
    }
}

@Test func dependencyDiagnosticsPreserveRawCaseMissingAndMalformedReferencesWithoutFalseBlocking() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let prerequisite = try await replica.create(id: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!, attributes: ["description": "Prerequisite", "status": "pending"])
    let uppercase = prerequisite.id.uuidString
    let missing = "aaaaaaaa-0000-4000-8000-000000000004"
    let source = try await replica.create(id: UUID(), attributes: ["description": "Diagnostics", "status": "pending", "dep_\(uppercase)": "keep uppercase", "dep_\(missing)": "missing opaque", "dep_bad reference": "retain invalid", "depends": "opaque legacy", "opaque": "retain"])
    let links = try await manager.dependencyLinks(id: source.id)
    #expect(links.first(where: { $0.reference == uppercase })?.issue == .missingReference)
    #expect(links.first(where: { $0.reference == missing })?.issue == .missingReference)
    #expect(links.first(where: { $0.reference == "bad reference" })?.issue == .invalidReference)
    let availability = try await manager.availability(id: source.id)
    #expect(!availability.isBlocked)
    #expect(availability.isAvailable)
    #expect(availability.diagnostics.count == 3)
    let unrelated = try await manager.update(id: source.id, changes: ["description": "Edited unrelated field"])
    #expect(unrelated.attributes["dep_\(uppercase)"] == "keep uppercase")
    #expect(unrelated.attributes["dep_bad reference"] == "retain invalid")
    #expect(unrelated.attributes["depends"] == "opaque legacy")
    let repaired = try await manager.removeDependency(id: source.id, reference: "bad reference")
    #expect(repaired.attributes["dep_bad reference"] == nil)
    #expect(repaired.attributes["dep_\(uppercase)"] == "keep uppercase")
    #expect(repaired.attributes["dep_\(missing)"] == "missing opaque")
    #expect(repaired.attributes["opaque"] == "retain")
}

@Test func storedCyclesAreDiagnosedAndTerminalPrerequisitesUnblockWithoutLosingLinks() async throws {
    let replica = TestReplica()
    let firstID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    let secondID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000002")!
    _ = try await replica.create(id: firstID, attributes: ["description": "First", "status": "pending", "dep_\(secondID.uuidString.lowercased())": "x", "dep_\(firstID.uuidString.lowercased())": "self opaque"])
    _ = try await replica.create(id: secondID, attributes: ["description": "Second", "status": "pending", "dep_\(firstID.uuidString.lowercased())": "x"])
    let manager = TaskManager(replica: replica)
    let links = try await manager.dependencyLinks(id: firstID)
    #expect(links.first(where: { $0.reference == firstID.uuidString.lowercased() })?.issue == .selfReference)
    #expect(links.first(where: { $0.reference == secondID.uuidString.lowercased() })?.issue == .cycle)
    #expect(try await manager.availability(id: firstID).isBlocked)
    for status in ["completed", "deleted", "recurring", "unknown"] {
        let target = try await replica.create(id: UUID(), attributes: ["description": status, "status": status])
        let owner = try await replica.create(id: UUID(), attributes: ["description": "Owner", "status": "pending", "dep_\(target.id.uuidString.lowercased())": "x"])
        #expect(try await manager.availability(id: owner.id).isBlocked == (status != "completed" && status != "deleted"))
        #expect(try await manager.task(id: owner.id).dependencyReferences == [target.id.uuidString.lowercased()])
    }
}

@Test func concurrentOppositeDependencyLinksCannotCreateANewCycle() async throws {
    for _ in 0..<10 {
        let manager = TaskManager(replica: TestReplica())
        let first = try await manager.create(TaskDraft(description: "First"))
        let second = try await manager.create(TaskDraft(description: "Second"))
        async let forward = dependencyAttempt(manager, id: first.id, prerequisiteID: second.id)
        async let reverse = dependencyAttempt(manager, id: second.id, prerequisiteID: first.id)
        let successes = await [forward, reverse].filter { $0 }.count
        #expect(successes == 1)
        #expect(try await manager.tasks().flatMap(\.dependencyReferences).count == 1)
    }
}

private func dependencyAttempt(_ manager: TaskManager, id: UUID, prerequisiteID: UUID) async -> Bool {
    do { _ = try await manager.addDependency(id: id, prerequisiteID: prerequisiteID); return true }
    catch { return false }
}

@Test func filteredViewSnapshotRetainsAllPrerequisitesForPureAvailabilityUpdates() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) })
    let target = try await manager.create(TaskDraft(description: "Outside view", attributes: ["project": "Other"]))
    let source = try await manager.create(TaskDraft(description: "In view", attributes: ["project": "Selected", "scheduled": "1791928800"]))
    _ = try await manager.addDependency(id: source.id, prerequisiteID: target.id)
    let snapshot = try await manager.viewSnapshot(query: .today, project: .project("Selected"))
    #expect(snapshot.tasks.map(\.id) == [source.id])
    #expect(Set(snapshot.allTasks.map(\.id)) == [target.id, source.id])
    #expect(snapshot.projects == ["Other", "Selected"])
    #expect(snapshot.tasks[0].availability(at: Date(timeIntervalSince1970: 1791972000), tasks: snapshot.allTasks).isBlocked)
    _ = try await manager.complete(id: target.id)
    let updated = try await manager.viewSnapshot(query: .today, project: .project("Selected"))
    #expect(!updated.tasks[0].availability(at: Date(timeIntervalSince1970: 1791972000), tasks: updated.allTasks).isBlocked)
    #expect(updated.tasks[0].dependencyReferences == [target.id.uuidString.lowercased()])
}
