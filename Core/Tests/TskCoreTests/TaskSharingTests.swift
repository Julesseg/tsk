import Foundation
import Testing
import TskCore

@Test func sharedTextAndLinkBecomeOnePlainTaskWithTheCompleteDescription() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let description = "Read this article\nKeep café e\u{301} and the full second line.\n\nhttps://example.com/review?q=caf%C3%A9#notes"
    let saved = try await manager.captureSharedTask([.text("Read this article\nKeep café e\u{301} and the full second line."), .url(URL(string: "https://example.com/review?q=caf%C3%A9#notes")!)])
    #expect(saved.description.matchesBytes(description))
    #expect(saved.attributes == ["description": description, "status": "pending", "entry": "1792144800", "modified": "1792144800"])
    #expect(try await manager.tasks() == [saved])
}

@Test func aSharedLinkUsesTheURLAsTheDescriptionWithoutAnAnnotation() async throws {
    let manager = TaskManager(replica: TestReplica())
    let saved = try await manager.captureSharedTask([.url(URL(string: "https://example.com/read?a=one#section")!)])
    #expect(saved.description == "https://example.com/read?a=one#section")
    #expect(saved.annotations.isEmpty && saved.tags.isEmpty && saved.attributes["project"] == nil)
    #expect(saved.attributes["due"] == nil && saved.attributes["scheduled"] == nil && saved.attributes["priority"] == nil)
}

@Test func unsupportedSharedFilesAndEmptyInputsNeverCreateATask() async throws {
    let manager = TaskManager(replica: TestReplica())
    await #expect(throws: TaskSharingError.noSupportedContent) { try await manager.captureSharedTask([.text(" \n ")]) }
    await #expect(throws: TaskSharingError.fileURL) { try await manager.captureSharedTask([.url(URL(fileURLWithPath: "/tmp/ignored.txt"))]) }
    #expect(try await manager.tasks().isEmpty)
    let saved = try await manager.captureSharedTask([.text("  A plain task\nWith another line  ")])
    #expect(saved.description == "A plain task\nWith another line")
}
