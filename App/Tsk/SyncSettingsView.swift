import SwiftUI

struct SyncSettingsView: View {
    let synchronization: SynchronizationStore
    let tasks: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var clientID = ""
    @State private var secret = ""
    @State private var savedConnection = false

    private var hasUnsavedChanges: Bool {
        guard let configuration = synchronization.configuration else { return true }
        return serverURL.trimmingCharacters(in: .whitespacesAndNewlines) != configuration.serverURL
            || UUID(uuidString: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) != configuration.clientID
            || secret != configuration.encryptionSecret
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("sync-server-url")
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("sync-client-id")
                    SecureField("Encryption secret", text: $secret)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("sync-encryption-secret")
                    Button("Save connection") {
                        Task { savedConnection = await synchronization.saveConnection(serverURL: serverURL, clientID: clientID, secret: secret) }
                    }
                    .accessibilityIdentifier("save-sync-connection")
                    if savedConnection {
                        Text("Connection saved on this device. Automatic synchronization will verify server access.")
                            .font(.footnote).accessibilityIdentifier("sync-connection-saved")
                    }
                }
                .disabled(synchronization.isSyncing || synchronization.isSaving)
                Section("Synchronization") {
                    Text(synchronization.status).accessibilityIdentifier("sync-status")
                    if let date = synchronization.lastSynchronized {
                        LabeledContent("Last synchronized", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button(synchronization.error == nil ? "Sync now" : "Retry synchronization") {
                        Task {
                            _ = await synchronization.synchronize()
                            await tasks.reload()
                        }
                    }
                    .disabled(synchronization.configuration == nil || synchronization.isSyncing || hasUnsavedChanges)
                    .accessibilityIdentifier("sync-now")
                    if synchronization.configuration != nil && hasUnsavedChanges {
                        Text("Save connection changes before synchronizing.").font(.footnote)
                    }
                    if synchronization.isSyncing { ProgressView("Contacting server") }
                    if let error = synchronization.error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("sync-error")
                    }
                }
                Section {
                    Text("Use the same server, client ID and encryption secret as your Taskwarrior clients. Local saves work offline. Synchronization runs after task changes, app opening and restored connectivity; background opportunities depend on iOS. Saving a connection does not mean synchronization succeeded.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if synchronization.configuration != nil {
                        Text("Disconnecting keeps all tasks saved on this device.").font(.footnote)
                    }
                }
            }
            .navigationTitle("Synchronization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if synchronization.configuration != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                await synchronization.disconnect()
                                serverURL = ""
                                clientID = ""
                                secret = ""
                                savedConnection = false
                            }
                        }
                        .disabled(synchronization.isSyncing || synchronization.isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: serverURL) { savedConnection = false }
            .onChange(of: clientID) { savedConnection = false }
            .onChange(of: secret) { savedConnection = false }
            .task {
                await synchronization.loadConfiguration()
                serverURL = synchronization.configuration?.serverURL ?? ""
                clientID = synchronization.configuration?.clientID.uuidString ?? ""
                secret = synchronization.configuration?.encryptionSecret ?? ""
            }
        }
    }
}
