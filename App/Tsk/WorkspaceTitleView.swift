import SwiftUI

struct WorkspaceTitleView: View {
    let title: String
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Synchronizing")
                    .accessibilityIdentifier("workspace-sync-progress")
            }
        }
    }
}
