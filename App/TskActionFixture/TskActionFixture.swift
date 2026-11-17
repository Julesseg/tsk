import SwiftUI
import UIKit

@main struct TskActionFixtureApp: App {
    var body: some Scene { WindowGroup { ActionFixtureView() } }
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
