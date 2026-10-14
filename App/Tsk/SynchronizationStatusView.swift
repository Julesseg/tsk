import SwiftUI

struct SynchronizationStatusView: View {
    let synchronization: SynchronizationStore
    var backgroundError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if synchronization.isSyncing { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(synchronization.status).font(.caption).accessibilityIdentifier("task-sync-status")
                if let backgroundError { Text(backgroundError).font(.caption).foregroundStyle(.secondary) }
                if let error = synchronization.error {
                    Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("task-sync-error")
                }
            }
            Spacer(minLength: 0)
            if synchronization.error != nil && synchronization.configuration != nil {
                Button("Retry") { Task { _ = await synchronization.synchronize() } }
                    .font(.caption).accessibilityIdentifier("retry-task-sync")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
