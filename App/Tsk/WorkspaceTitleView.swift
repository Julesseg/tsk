import SwiftUI

struct WorkspaceTitleView: View {
    let title: String
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("workspace-title-text")
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Synchronizing")
                    .accessibilityIdentifier("workspace-sync-progress")
            }
        }
    }
}
