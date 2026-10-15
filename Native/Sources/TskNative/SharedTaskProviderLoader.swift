#if canImport(UniformTypeIdentifiers)
import Foundation
import UniformTypeIdentifiers
import TskCore

@available(iOS 14, macOS 11, *)
@MainActor public enum SharedTaskProviderLoader {
    public static func load(_ providers: [NSItemProvider]) async throws -> [SharedTaskItem] {
        var items: [SharedTaskItem] = []
        for provider in providers {
            try Task.checkCancellation()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { continue }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                items.append(try await load(provider, identifier: UTType.url.identifier, url: true))
            }
            let text = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText.identifier : UTType.text.identifier
            if provider.hasItemConformingToTypeIdentifier(text) { items.append(try await load(provider, identifier: text, url: false)) }
        }
        try Task.checkCancellation()
        return items
    }

    private static func load(_ provider: NSItemProvider, identifier: String, url: Bool) async throws -> SharedTaskItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { @Sendable value, error in
                if let error { continuation.resume(throwing: error); return }
                if url, let value = value as? URL { continuation.resume(returning: .url(value)); return }
                let text: String?
                if let string = value as? String { text = string }
                else if let data = value as? Data { text = String(data: data, encoding: .utf8) }
                else { text = nil }
                if let text {
                    if url, let value = URL(string: text) { continuation.resume(returning: .url(value)) }
                    else if !url { continuation.resume(returning: .text(text)) }
                    else { continuation.resume(throwing: SharedProviderError.unreadable) }
                } else { continuation.resume(throwing: SharedProviderError.unreadable) }
            }
        }
    }
}

private enum SharedProviderError: Error, LocalizedError {
    case unreadable
    var errorDescription: String? { "The source app could not provide readable text or a link. Retry sharing from that app." }
}
#endif
