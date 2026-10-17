import Foundation
import Testing
import TskCore

@Test func sharedTextAndURLBecomeAnEditableDraftAndOneDurableCompatibleTask() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let url = URL(string: "https://example.com/review?q=caf%C3%A9#notes")!
    var shared = try TaskManager.sharedDraft(from: [.text("Read this article\nKeep café e\u{301} and the full second line."), .url(url)])
    #expect(shared.task.description == "Read this article")
    #expect(shared.content.matchesBytes("Read this article\nKeep café e\u{301} and the full second line.\n\nhttps://example.com/review?q=caf%C3%A9#notes"))
    #expect(try await manager.tasks().isEmpty)
    shared.task.description = "Review shared article"
    shared.task.project = "Research.Reading"
    try shared.task.addTag("reference")
    shared.task.plannedDate = Date(timeIntervalSince1970: 1792108800)
    shared.task.deadline = Date(timeIntervalSince1970: 1792231200)
    let saved = try await manager.captureSharedTask(shared)
    #expect(saved.description == "Review shared article")
    #expect(saved.project == "Research.Reading" && saved.tags == ["reference"])
    #expect(saved.attributes["scheduled"] == "1792108800" && saved.attributes["due"] == "1792231200")
    #expect(saved.annotations.first?.text.matchesBytes(shared.content) == true)
    #expect(saved.annotations.first?.reference.rawValue == "annotation_1792144800")
    #expect(try await manager.tasks() == [saved])
}

@Test func unsupportedSharedFilesAndEmptyInputsNeverCreateATaskAndDraftEditsRemainValidated() async throws {
    let manager = TaskManager(replica: TestReplica())
    #expect(throws: TaskSharingError.noSupportedContent) { try TaskManager.sharedDraft(from: [.text(" \n ")]) }
    #expect(throws: TaskSharingError.fileURL) { try TaskManager.sharedDraft(from: [.url(URL(fileURLWithPath: "/tmp/ignored.txt"))]) }
    var draft = try TaskManager.sharedDraft(from: [.url(URL(string: "https://example.com/a")!)])
    #expect(draft.task.description == "https://example.com/a")
    draft.task.description = " "
    await #expect(throws: TaskManagementError.emptyDescription) { try await manager.captureSharedTask(draft) }
    #expect(try await manager.tasks().isEmpty)
    draft.task.description = "Edited link"
    draft.content = "User edited retained text\nhttps://example.com/a"
    let task = try await manager.captureSharedTask(draft)
    #expect(task.annotations.first?.text == draft.content)
}
