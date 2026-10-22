import SwiftUI
import UIKit

struct CompactWorkspaceTabs: UIViewControllerRepresentable {
    let identifiers: [String]

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configure(identifiers)
    }

    final class Controller: UIViewController {
        private var identifiers: [String] = []

        func configure(_ identifiers: [String]) {
            guard self.identifiers != identifiers else { return }
            self.identifiers = identifiers
            Task { @MainActor [weak self] in self?.apply() }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        private func apply() {
            guard let tabBarController, !identifiers.isEmpty else { return }
            let nativeIDs = tabBarController.tabs.map(\.identifier)
            guard Set(identifiers).isSubset(of: Set(nativeIDs)), tabBarController.compactTabIdentifiers != identifiers else { return }
            tabBarController.compactTabIdentifiers = identifiers
        }
    }
}
