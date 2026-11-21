import Foundation
import Testing
import TskCore
import TskNative

@Test func serverConfigurationSurvivesRelaunchWithoutEnteringTaskAttributes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SyncConfigurationStore(directory: directory)
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated secret with spaces")
    try await store.save(configuration)
    #expect(try await SyncConfigurationStore(directory: directory).load() == configuration)
    try await store.remove()
    #expect(try await store.load() == nil)
}

@Test func failedNativeSynchronizationPreservesLocallyCommittedTask() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let saved = try await manager.create(TaskDraft(description: "Offline task survives sync failure", attributes: ["opaque": "exactly preserved"]))
    let unavailable = try SyncConfiguration(serverURL: "http://127.0.0.1:1", clientID: UUID(), encryptionSecret: "isolated-secret")
    do {
        _ = try await manager.synchronize(using: unavailable)
        Issue.record("Unavailable server must fail synchronization")
    } catch let failure as SynchronizationError {
        if case .failed(let message) = failure {
            #expect(message.contains("Failed to synchronize with server"))
        } else { Issue.record("Expected an actual server failure, received \(failure)") }
    }
    #expect(try await manager.task(id: saved.id) == saved)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func realEncryptedTaskwarriorSyncConvergesBothWaysAndRetainsOpaqueFields() async throws {
    let environment = ProcessInfo.processInfo.environment
    let binary = try #require(environment["TSK_TASKWARRIOR_BINARY"])
    let rawClientID = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClientID))
    let configuration = try SyncConfiguration(serverURL: try #require(environment["TSK_SYNC_TEST_URL"]), clientID: clientID, encryptionSecret: try #require(environment["TSK_SYNC_TEST_SECRET"]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = Date(timeIntervalSince1970: 1792400400)
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("native")), now: { today }, calendar: calendar)
    var draft = TaskDraft(description: "Phone to desktop", attributes: ["customOpaque": "phone original", "annotation_1792015200": "Retain native annotation", "due": "1792144800"])
    draft.setScheduled(TaskScheduledDate(date: Date(timeIntervalSince1970: 1792195200), hasTime: true))
    let native = try await manager.create(draft)
    _ = try await manager.synchronize(using: configuration)
    let desktop = directory.appendingPathComponent("desktop")
    let taskrc = directory.appendingPathComponent("taskrc")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    uda.customOpaque.type=string
    uda.customOpaque.label=Opaque
    uda.tsk_scheduled_precision.type=string
    uda.tsk_planner_order.type=string
    uda.tsk_project_order.type=string
    uda.tsk_completion_page.type=string
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    func task(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=off"] + arguments
        var executionEnvironment = environment
        executionEnvironment["TASKRC"] = taskrc.path
        executionEnvironment["TASKDATA"] = desktop.path
        process.environment = executionEnvironment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SynchronizationError.failed(String(decoding: error, as: UTF8.self))
        }
        return data
    }
    #expect(String(decoding: try task(["_version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "3.5.0")
    _ = try task(["sync"])
    let exported = try #require(JSONSerialization.jsonObject(with: task([native.id.uuidString.lowercased(), "export"])) as? [[String: Any]])
    let onDesktop = try #require(exported.first)
    #expect(onDesktop["uuid"] as? String == native.id.uuidString.lowercased())
    #expect(onDesktop["description"] as? String == "Phone to desktop")
    #expect(onDesktop["customOpaque"] as? String == "phone original")
    #expect(onDesktop["scheduled"] as? String == "20261017T000000Z")
    #expect(onDesktop["due"] as? String == "20261016T100000Z")
    _ = try task([native.id.uuidString.lowercased(), "modify", "description:Desktop edit", "customOpaque:desktop opaque"])
    let remoteDescription = "Desktop to phone \(UUID().uuidString)"
    _ = try task(["add", remoteDescription, "project:Interop"])
    let added = try #require(JSONSerialization.jsonObject(with: task(["description.is:\(remoteDescription)", "export"])) as? [[String: Any]])
    let rawDesktopID = try #require(added.first?["uuid"] as? String)
    let desktopID = try #require(UUID(uuidString: rawDesktopID))
    _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    let peer = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("peer")), now: { today }, calendar: calendar)
    _ = try await peer.synchronize(using: configuration)
    #expect(try await peer.task(id: native.id).scheduled(calendar: calendar)?.hasTime == true)
    let updated = try await manager.task(id: native.id)
    #expect(updated.scheduled(calendar: calendar)?.hasTime == true)
    #expect(updated.plannedDate == native.plannedDate)
    #expect(updated.description == "Desktop edit")
    #expect(updated.attributes["customOpaque"] == "desktop opaque")
    #expect(updated.attributes["annotation_1792015200"] == "Retain native annotation")
    #expect(try await manager.task(id: desktopID).description == remoteDescription)
    #expect(try await manager.task(id: desktopID).attributes["project"] == "Interop")
    _ = try task([native.id.uuidString.lowercased(), "modify", "scheduled:2026-10-18T00:00:00Z"])
    _ = try task(["sync"])
    _ = try await manager.synchronize(using: configuration)
    let externallyMoved = try await manager.task(id: native.id)
    #expect(externallyMoved.plannedDate == Date(timeIntervalSince1970: 1792281600))
    #expect(externallyMoved.scheduled(calendar: calendar)?.hasTime == false)
    var untimed = TaskRowDraft(task: externallyMoved)
    untimed.taskDraft.setScheduled(TaskScheduledDate(date: Date(timeIntervalSince1970: 1792400400), hasTime: false))
    _ = try await manager.updateRow(untimed)
    _ = try await manager.synchronize(using: configuration)
    _ = try task(["sync"])
    _ = try task([native.id.uuidString.lowercased(), "modify", "description:Untimed returned"])
    _ = try task(["sync"])
    let final = try await manager.synchronize(using: configuration)
    _ = try await peer.synchronize(using: configuration)
    #expect(try await peer.task(id: native.id).scheduled(calendar: calendar)?.hasTime == false)
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("native")))
    let returned = try await reopened.task(id: native.id)
    #expect(returned.description == "Untimed returned")
    #expect(returned.scheduled(calendar: calendar)?.hasTime == false)
    #expect(returned.plannedDate == Date(timeIntervalSince1970: 1792400400))
    #expect(returned.deadline == Date(timeIntervalSince1970: 1792144800))
    #expect(returned.attributes["customOpaque"] == "desktop opaque")
    #expect(returned.attributes["annotation_1792015200"] == "Retain native annotation")
    #expect(final.filter { $0.id == native.id }.count == 1)
    #expect(final.filter { $0.id == desktopID }.count == 1)
    _ = try await manager.update(id: native.id, changes: ["project": "Order"])
    var companionDraft = TaskDraft(description: "Synced ordered neighbor", attributes: ["project": "Order", "opaque": "rank transport"])
    companionDraft.setScheduled(returned.scheduled(calendar: calendar))
    let companion = try await manager.create(companionDraft)
    let beforeOrder = try await manager.dayPage(on: today)
    var drag = try TaskDragSession(tasks: beforeOrder, ids: [beforeOrder[1].id], context: .day(today), calendar: calendar)
    drag.cross(beforeOrder[0].id)
    _ = try await manager.drop(drag)
    let expectedDayOrder = [beforeOrder[1].id, beforeOrder[0].id]
    let projectOrder = try await manager.tasks(query: .unfinished, project: .project("Order"))
    drag = try TaskDragSession(tasks: projectOrder, ids: [projectOrder[1].id], context: .project("Order"), calendar: calendar)
    drag.cross(projectOrder[0].id)
    _ = try await manager.drop(drag)
    _ = try await manager.synchronize(using: configuration)
    _ = try task(["sync"])
    _ = try task([companion.id.uuidString.lowercased(), "modify", "description:Rank returned through Taskwarrior"])
    _ = try task(["sync"])
    _ = try await peer.synchronize(using: configuration)
    #expect(try await peer.dayPage(on: today).map(\.id) == expectedDayOrder)
    #expect(try await peer.tasks(query: .unfinished, project: .project("Order")).map(\.id) == [projectOrder[1].id, projectOrder[0].id])
    #expect(try await peer.task(id: companion.id).description == "Rank returned through Taskwarrior")
    #expect(try await peer.task(id: native.id).scheduled(calendar: calendar) == returned.scheduled(calendar: calendar))
    #expect(try await peer.task(id: native.id).deadline == returned.deadline)
    let completed = try await manager.complete(id: native.id)
    let retainedPage = try #require(completed.attributes["tsk_completion_page"])
    _ = try await manager.synchronize(using: configuration)
    _ = try task(["sync"])
    let completedExport = try #require(JSONSerialization.jsonObject(with: task([native.id.uuidString.lowercased(), "export"])) as? [[String: Any]])
    #expect(completedExport.first?["tsk_completion_page"] as? String == retainedPage)
    _ = try task([native.id.uuidString.lowercased(), "modify", "customOpaque:completed desktop roundtrip"])
    _ = try task(["sync"])
    let historyPeer = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("independent-history-peer")), now: { today }, calendar: calendar)
    _ = try await historyPeer.synchronize(using: configuration)
    #expect(try await historyPeer.dayPage(on: today).map(\.id) == expectedDayOrder)
    #expect(try await historyPeer.task(id: native.id).status == "completed")
    #expect(try await historyPeer.task(id: native.id).attributes["tsk_completion_page"] == retainedPage)
    #expect(try await historyPeer.task(id: native.id).attributes["customOpaque"] == "completed desktop roundtrip")
    #expect(try await historyPeer.task(id: native.id).scheduled(calendar: calendar) == completed.scheduled(calendar: calendar))
    #expect(try await historyPeer.task(id: native.id).deadline == completed.deadline)
    let historyRelaunch = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("independent-history-peer")), now: { today }, calendar: calendar)
    #expect(try await historyRelaunch.dayPage(on: today).map(\.id) == expectedDayOrder)
    #expect(try await historyRelaunch.tasks(query: .unfinished, project: .project("Order")).map(\.id) == [companion.id])
    let wrongSecret = try SyncConfiguration(serverURL: configuration.serverURL, clientID: configuration.clientID, encryptionSecret: "wrong isolated secret")
    let other = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("wrong-secret")))
    let retained = try await other.create(TaskDraft(description: "Wrong credentials still preserve offline capture"))
    await #expect(throws: (any Error).self) { try await other.synchronize(using: wrongSecret) }
    #expect(try await other.task(id: retained.id) == retained)
}
