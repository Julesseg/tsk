import Foundation
import Testing
import TskCore
import TskNative
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers

@available(macOS 11, iOS 14, *)
@Test @MainActor func actualItemProvidersRetainTextAndURLAndSharedParticipantCaptureReopensInTheApp() async throws {
    let body = "Shared café e\u{301}\nFull text remains available"
    let url = URL(string: "https://example.com/share?q=retained#source")!
    let providers = [NSItemProvider(item: body as NSString, typeIdentifier: UTType.plainText.identifier), NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)]
    let items = try await SharedTaskProviderLoader.load(providers)
    let draft = try TaskManager.sharedDraft(from: items)
    #expect(draft.content.matchesBytes(body + "\n\n" + url.absoluteString))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let group = root.appendingPathComponent("shared"), legacy = root.appendingPathComponent("private")
    #expect(throws: (any Error).self) { try TaskChampionSession.prepareShared(container: group, legacy: legacy, allowMigration: false) }
    let directory = try TaskChampionSession.prepareShared(container: group, legacy: legacy)
    let participant = try TaskChampionSession.prepareShared(container: group, legacy: legacy, allowMigration: false)
    let manager = try await TaskChampionSession.open(directory: participant)
    let task = try await manager.captureSharedTask(draft)
    let app = try await TaskChampionSession.open(directory: directory)
    #expect(try await app.task(id: task.id) == task)
    #expect(task.annotations.first?.text.matchesBytes(draft.content) == true)
}
#endif

@Test func sharedCaptureStorageFailureNeverAcknowledgesATaskAndRetryKeepsItsContent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let before = try await manager.create(TaskDraft(description: "Existing task", attributes: ["opaque": "retained"]))
    let draft = try TaskManager.sharedDraft(from: [.text("Unsaved shared text"), .url(URL(string: "https://example.com/retry")!)])
    try shareSQL(directory, "CREATE TRIGGER fail_share BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'actual share save fixture failure'); END;")
    await #expect(throws: (any Error).self) { try await manager.captureSharedTask(draft) }
    #expect(try await manager.tasks() == [before])
    try shareSQL(directory, "DROP TRIGGER fail_share;")
    let saved = try await manager.captureSharedTask(draft)
    #expect(saved.annotations.first?.text == "Unsaved shared text\n\nhttps://example.com/retry")
    #expect(try await manager.task(id: before.id) == before)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func sharedFactoryCaptureAutomaticallySyncsAndTaskwarriorReadsCompatibleTextLinkOrganizationAndDates() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("shared")
    let rawClient = try #require(env["TSK_SYNC_TEST_CLIENT_ID"])
    let configuration = try SyncConfiguration(serverURL: #require(env["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(env["TSK_SYNC_TEST_SECRET"]))
    try await SyncConfigurationStore(directory: directory).save(configuration)
    let manager = try await TaskChampionSession.open(directory: directory)
    let states = await manager.synchronizationUpdates()
    var draft = try TaskManager.sharedDraft(from: [.text("Shared body\nPreserve café e\u{301}"), .url(URL(string: "https://example.com/read?q=one#source")!)])
    draft.task.description = "Shared capture interop"
    draft.task.project = "Shared.Reading"
    try draft.task.addTag("reference")
    draft.task.plannedDate = Date(timeIntervalSince1970: 1792108800)
    draft.task.deadline = Date(timeIntervalSince1970: 1792231200)
    let saved = try await manager.captureSharedTask(draft)
    for await state in states {
        if case .synchronized = state { break }
        if case .failed(let message) = state { throw TaskManagementError.storage(String(describing: message)) }
    }
    let peer = try await TaskChampionSession.open(directory: root.appendingPathComponent("peer"))
    _ = try await peer.synchronize(using: configuration)
    #expect(try await peer.task(id: saved.id) == saved)
    let config = root.appendingPathComponent("taskrc")
    try "data.location=\(root.appendingPathComponent("peer").path)\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: try #require(env["TSK_TASKWARRIOR_BINARY"]))
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off", saved.id.uuidString.lowercased(), "export"]
    process.environment = env.merging(["TASKRC": config.path, "TASKDATA": root.appendingPathComponent("peer").path, "TZ": "UTC"]) { _, value in value }
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(String(decoding: diagnostics, as: UTF8.self))")
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let row = try #require(rows.first)
    #expect(row["uuid"] as? String == saved.id.uuidString.lowercased())
    #expect(row["description"] as? String == "Shared capture interop")
    #expect(row["project"] as? String == "Shared.Reading")
    #expect(row["tags"] as? [String] == ["reference"])
    #expect(row["scheduled"] as? String == "20261016T000000Z")
    #expect(row["due"] as? String == "20261017T100000Z")
    let notes = try #require(row["annotations"] as? [[String: String]])
    #expect(notes.first?["description"]?.matchesBytes(draft.content) == true)
    if let path = env["TSK_SHARE_PROOF_PATH"] { try data.write(to: URL(fileURLWithPath: path)) }
}

private func shareSQL(_ directory: URL, _ query: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, query]
    let errors = Pipe(); process.standardError = errors
    try process.run(); process.waitUntilExit()
    let error = errors.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: error, as: UTF8.self)) }
}

#if canImport(UniformTypeIdentifiers)
@available(macOS 11, iOS 14, *)
@Test @MainActor func fileItemProvidersDoNotBecomeStoredAttachmentPathsOrTasks() async throws {
    let provider = NSItemProvider(item: URL(fileURLWithPath: "/tmp/not-a-task-attachment.txt") as NSURL, typeIdentifier: UTType.fileURL.identifier)
    let items = try await SharedTaskProviderLoader.load([provider])
    #expect(throws: TaskSharingError.noSupportedContent) { try TaskManager.sharedDraft(from: items) }
}
#endif
