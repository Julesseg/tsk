import Foundation
import Testing
import TskCore
import TskNative
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers

@available(macOS 11, iOS 14, *)
@Test @MainActor func actualItemProvidersCreateOnePlainTaskThatReopensInTheApp() async throws {
    let body = "Shared café e\u{301}\nFull text remains available"
    let url = URL(string: "https://example.com/share?q=retained#source")!
    let providers = [NSItemProvider(item: body as NSString, typeIdentifier: UTType.plainText.identifier), NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)]
    let items = try await SharedTaskProviderLoader.load(providers)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let group = root.appendingPathComponent("shared"), legacy = root.appendingPathComponent("private")
    #expect(throws: (any Error).self) { try TaskChampionSession.prepareShared(container: group, legacy: legacy, allowMigration: false) }
    let directory = try TaskChampionSession.prepareShared(container: group, legacy: legacy)
    let participant = try TaskChampionSession.prepareShared(container: group, legacy: legacy, allowMigration: false)
    let manager = try await TaskChampionSession.open(directory: participant)
    let task = try await manager.captureSharedTask(items)
    let app = try await TaskChampionSession.open(directory: directory)
    #expect(try await app.task(id: task.id) == task)
    #expect(task.description.matchesBytes(body + "\n\n" + url.absoluteString))
    #expect(task.annotations.isEmpty && task.tags.isEmpty && task.attributes["project"] == nil)
}

@available(macOS 11, iOS 14, *)
@Test @MainActor func aURLProviderWithATextRepresentationCreatesOnlyOneURLDescription() async throws {
    let provider = NSItemProvider()
    let url = "https://example.com/one-link"
    for type in [UTType.url, UTType.plainText] {
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(Data(url.utf8), nil)
            return nil
        }
    }
    let items = try await SharedTaskProviderLoader.load([provider])
    #expect(items.count == 1)
    #expect(try TaskManager.sharedDescription(from: items) == url)
}

@available(macOS 11, iOS 14, *)
@Test @MainActor func fileItemProvidersDoNotBecomeStoredAttachmentPathsOrTasks() async throws {
    let provider = NSItemProvider(item: URL(fileURLWithPath: "/tmp/not-a-task-attachment.txt") as NSURL, typeIdentifier: UTType.fileURL.identifier)
    let items = try await SharedTaskProviderLoader.load([provider])
    #expect(throws: TaskSharingError.noSupportedContent) { try TaskManager.sharedDescription(from: items) }
}
#endif
