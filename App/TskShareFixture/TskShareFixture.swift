import SwiftUI
import UIKit
import LinkPresentation

@main struct TskShareFixtureApp: App {
    var body: some Scene { WindowGroup { ShareFixtureView() } }
}

private struct ShareFixtureView: View {
    @State private var showing = false
    var body: some View {
        VStack(spacing: 24) {
            Text("tsk isolated sharing fixture").font(.title)
            Text("Presents a real system share sheet with text and a URL. This app does not access tsk storage.")
            Button("Share text and link") { showing = true }.accessibilityIdentifier("share-fixture-present")
        }.padding().sheet(isPresented: $showing) { ShareFixtureSheet(complete: { showing = false }) }
    }
}

private struct ShareFixtureSheet: UIViewControllerRepresentable {
    let complete: @MainActor @Sendable () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let token = ProcessInfo.processInfo.environment["TSK_SHARE_FIXTURE_TOKEN"] ?? "isolated"
        let text = "Shared article \(token)\nFull shared text café e\u{301}"
        let url = URL(string: "https://example.com/tsk-share?fixture=\(token)#retained")!
        let controller = UIActivityViewController(activityItems: [text, ShareFixtureURL(url: url)], applicationActivities: nil)
        let complete = complete
        controller.completionWithItemsHandler = { @Sendable _, _, _, _ in Task { @MainActor in complete() } }
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 1, y: 1, width: 1, height: 1)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class ShareFixtureURL: NSObject, UIActivityItemSource {
    let url: URL
    init(url: URL) { self.url = url }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = "tsk isolated sharing fixture"
        return metadata
    }
}
