import SwiftUI
import UIKit
import LinkPresentation

@main struct TskShareFixtureApp: App {
    var body: some Scene { WindowGroup {
        if ProcessInfo.processInfo.environment["TSK_ACTION_FIXTURE_URL"] != nil { ActionFixtureView() }
        else { ShareFixtureView() }
    } }
}

private struct ShareFixtureView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShareFixtureController { ShareFixtureController() }
    func updateUIViewController(_ uiViewController: ShareFixtureController, context: Context) {}
}

private final class ShareFixtureController: UIViewController {
    private let shareButton = UIButton(type: .system)
    private let result = UILabel()
    private var activityController: UIActivityViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "tsk isolated sharing fixture"
        title.font = .preferredFont(forTextStyle: .title1)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = "Presents a real system share sheet with text and a URL. This app does not access tsk storage."
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.numberOfLines = 0
        shareButton.setTitle("Share text and link", for: .normal)
        shareButton.accessibilityIdentifier = "share-fixture-present"
        shareButton.addAction(UIAction { [weak self] _ in self?.presentShare() }, for: .touchUpInside)
        result.text = "Ready"
        result.accessibilityIdentifier = "share-fixture-result"
        let content = UIStackView(arrangedSubviews: [title, detail, shareButton, result])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        prepareActivityController()
    }

    private func prepareActivityController() {
        let token = ProcessInfo.processInfo.environment["TSK_SHARE_FIXTURE_TOKEN"] ?? "isolated"
        let text = "Shared article \(token)\nFull shared text café e\u{301}"
        let url = URL(string: "https://example.com/tsk-share?fixture=\(token)#retained")!
        let mode = ProcessInfo.processInfo.environment["TSK_SHARE_FIXTURE_MODE"] ?? "both"
        let items: [Any] = mode == "text" ? [text] : mode == "url" ? [ShareFixtureURL(url: url)] : [text, ShareFixtureURL(url: url)]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { @Sendable [weak self] _, completed, _, error in
            let saved = completed && error == nil
            Task { @MainActor [weak self] in
                self?.result.text = saved ? "Saved" : "Not saved"
                self?.prepareActivityController()
            }
        }
        controller.popoverPresentationController?.sourceView = shareButton
        controller.popoverPresentationController?.sourceRect = shareButton.bounds
        activityController = controller
    }

    private func presentShare() {
        guard presentedViewController == nil, let controller = activityController else { return }
        activityController = nil
        result.text = "Sharing"
        controller.popoverPresentationController?.sourceRect = shareButton.bounds
        present(controller, animated: true)
    }
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

private struct ActionFixtureView: View {
    @State private var url = ProcessInfo.processInfo.environment["TSK_ACTION_FIXTURE_URL"] ?? "tsk://add?description=Fixture"
    @State private var callback = "No callback"
    @State private var delivery = "Ready"

    var body: some View {
        Form {
            Text("tsk action caller").font(.headline)
            TextField("Task URL", text: $url, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("action-fixture-url")
            Button("Open task URL") {
                guard let target = URL(string: url) else { delivery = "Invalid URL"; return }
                UIApplication.shared.open(target) { accepted in
                    Task { @MainActor in delivery = accepted ? "Delivered" : "Rejected" }
                }
            }.accessibilityIdentifier("action-fixture-open")
            Text(delivery).accessibilityIdentifier("action-fixture-delivery")
            Text(callback).textSelection(.enabled).accessibilityIdentifier("action-fixture-callback")
        }
        .onOpenURL { callback = $0.absoluteString }
    }
}
