import Foundation
import Testing
@testable import TskCore

@Test func rawFilterSelectsAllStoredStatesWithBooleanProjectAndTagPredicates() async throws {
    let manager = TaskManager(replica: TestReplica())
    let work = try await manager.create(TaskDraft(description: "Alpha", attributes: ["project": "Work", "tag_home": ""]))
    let nested = try await manager.create(TaskDraft(description: "Other", attributes: ["project": "Work.sub"]))
    _ = try await manager.create(TaskDraft(description: "Unrelated", attributes: ["project": "Artwork", "tag_home": ""]))
    _ = try await manager.complete(id: work.id)
    #expect(Set(try await manager.tasks(filter: "project:Work").map(\.id)) == [work.id, nested.id])
    #expect(try await manager.tasks(filter: "(project:Work and +home) or status:completed").map(\.id) == [work.id])
    #expect(try await manager.tasks(filter: "project:Work -home").map(\.id) == [nested.id])
    #expect(try await manager.tasks(filter: "project:Work xor project.is:Work").map(\.id) == [nested.id])
}

@Test func rawStatusFiltersUseWaitingStateWithoutRestrictingOtherPredicates() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1000) })
    let waiting = try await manager.create(TaskDraft(description: "Wait", attributes: ["wait": "1001"]))
    let pending = try await manager.create(TaskDraft(description: "Ready"))
    #expect(try await manager.tasks(filter: "status:pending").map(\.id) == [pending.id])
    #expect(try await manager.tasks(filter: "status:waiting").map(\.id) == [waiting.id])
    #expect(Set(try await manager.tasks(filter: "description.any:").map(\.id)) == [waiting.id, pending.id])
}

@Test func rawFiltersAgreeWithPinnedTaskwarrior350DarwinFixtures() async throws {
    struct Fixture: Decodable {
        struct Case: Decodable { let expression: String; let selected: [UUID] }
        let records: [TaskRecord]
        let cases: [Case]
    }
    let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "raw-taskwarrior-3.5.0", withExtension: "json", subdirectory: "Fixtures")))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let replica = TestReplica()
    for task in fixture.records { _ = try await replica.create(id: task.id, attributes: task.attributes) }
    let manager = TaskManager(replica: replica)
    for test in fixture.cases {
        #expect(Set(try await manager.tasks(filter: test.expression).map(\.id)) == Set(test.selected), "\(test.expression)")
    }
}

@Test func rawFilterReportsSyntaxSchemaRegexAndUnsupportedFeatureErrorsBeforeReadingResults() async throws {
    let manager = TaskManager(replica: TestReplica())
    for expression in ["(", "project:Work and", "or +home", "project.bogus:x", "project:'unclosed", "/unclosed"] {
        do {
            _ = try await manager.tasks(filter: expression)
            Issue.record("Expected an error for \(expression)")
        } catch let error as TaskFilterError {
            #expect(error.localizedDescription.contains("Filter"))
        }
    }
    await #expect(throws: TaskFilterError.unknownAttribute("opaque")) { try await manager.tasks(filter: "opaque:value") }
    do {
        _ = try await manager.tasks(filter: "/(?<=A)lpha/")
        Issue.record("ECMAScript must reject lookbehind even for an empty replica")
    } catch let error as TaskFilterError {
        if case .invalidRegex = error {} else { Issue.record("Expected invalidRegex, got \(error)") }
    }
    for expression in ["+LATEST", "recur:daily", "project.word:Work", "1", "project == Work"] {
        do {
            _ = try await manager.tasks(filter: expression)
            Issue.record("Expected an explicit unsupported error for \(expression)")
        } catch let error as TaskFilterError {
            if case .unsupported = error {} else { Issue.record("Expected unsupported, got \(error)") }
        }
    }
}

@Test func customViewSnapshotKeepsPrerequisitesOutsideTheRawExpression() async throws {
    let manager = TaskManager(replica: TestReplica())
    let prerequisite = try await manager.create(TaskDraft(description: "Prerequisite", attributes: ["project": "Other"]))
    let child = try await manager.create(TaskDraft(description: "Selected", attributes: ["project": "Work"]))
    _ = try await manager.addDependency(id: child.id, prerequisiteID: prerequisite.id)
    let snapshot = try await manager.viewSnapshot(filter: "project.is:Work")
    let selected = try #require(snapshot.tasks.first)
    #expect(snapshot.tasks.map(\.id) == [child.id])
    #expect(!selected.availability(at: Date(), tasks: snapshot.allTasks).isAvailable)
    _ = try await manager.complete(id: prerequisite.id)
    let refreshed = try await manager.viewSnapshot(filter: "project.is:Work")
    #expect(try #require(refreshed.tasks.first).availability(at: Date(), tasks: refreshed.allTasks).isAvailable)
}

@Test func ECMAScriptQueriesUseUTF8ByteLengthsIncludingEmbeddedNul() async throws {
    let manager = TaskManager(replica: TestReplica())
    let nul = try await manager.create(TaskDraft(description: "A\0B"))
    let unicode = try await manager.create(TaskDraft(description: "é"))
    #expect(try await manager.tasks(filter: "/^A.B$/").map(\.id) == [nul.id])
    #expect(try await manager.tasks(filter: "/^.$/").isEmpty)
    #expect(try await manager.tasks(filter: "/^..$/").map(\.id) == [unicode.id])
}
