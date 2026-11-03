import UIKit
import TskCore
import TskNative

@MainActor final class ShareViewController: UIViewController {
    private let diagnosticRequest = UUID()
    private var hasStarted = false

    deinit { TaskParticipantDiagnostics.endShareRequest(diagnosticRequest) }

    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            TaskParticipantDiagnostics.beginShareRequest(diagnosticRequest)
            await TaskParticipantDiagnostics.$shareRequest.withValue(diagnosticRequest) { await capture(context) }
        }
    }

    private func capture(_ context: NSExtensionContext) async {
        do {
            let inputs = context.inputItems.compactMap { $0 as? NSExtensionItem }
            var items = try await SharedTaskProviderLoader.load(inputs.flatMap { $0.attachments ?? [] })
            if items.isEmpty { items = inputs.compactMap { $0.attributedContentText?.string }.map(SharedTaskItem.text) }
            #if DEBUG && targetEnvironment(simulator)
            for case .url(let url) in items where url.scheme == "https" && url.host == "example.com" && url.path == "/tsk-share" {
                if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "fixture" })?.value, let token = UUID(uuidString: raw) {
                    TaskParticipantDiagnostics.enableShareFixture(token, request: diagnosticRequest)
                }
            }
            #endif
            let manager = try await TaskChampionSession.open(directory: TaskChampionSession.participantDirectory())
            let saved = try await manager.captureSharedTask(items)
            TaskParticipantDiagnostics.event("share.capture.durable-result", details: ["id": saved.id.uuidString])
            let request = diagnosticRequest
            context.completeRequest(returningItems: nil) { _ in TaskParticipantDiagnostics.endShareRequest(request) }
        } catch {
            TaskParticipantDiagnostics.endShareRequest(diagnosticRequest)
            context.cancelRequest(withError: error)
        }
    }
}
