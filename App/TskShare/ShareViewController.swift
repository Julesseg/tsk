import UIKit
import SwiftUI
import TskNative

@MainActor final class ShareViewController: UIViewController {
    private let diagnosticRequest = UUID()
    deinit { TaskParticipantDiagnostics.endShareRequest(diagnosticRequest) }
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        let host = UIHostingController(rootView: ShareCaptureRoot(context: context, diagnosticRequest: diagnosticRequest))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 600, height: 720)
    }
}
