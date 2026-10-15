import SwiftUI

struct SyncSettingsView: View {
    let synchronization: SynchronizationStore
    let tasks: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var clientID = ""
    @State private var secret = ""
    @State private var savedConnection = false
    @FocusState private var focusedField: Field?
    private enum Field { case server, client, secret }

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
                        .focused($focusedField, equals: .server)
                        .accessibilityIdentifier("sync-server-url")
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .client)
                        .accessibilityIdentifier("sync-client-id")
                    SecureField("Encryption secret", text: $secret)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .secret)
                        .accessibilityIdentifier("sync-encryption-secret")
                    Button("Save connection") {
                        focusedField = nil
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
                        focusedField = nil
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
            .accessibilityIdentifier("sync-settings-form")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { focusedField = nil }
                            .accessibilityIdentifier("dismiss-sync-keyboard")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle("Synchronization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if synchronization.configuration != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect", role: .destructive) {
                            focusedField = nil
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
                ToolbarItem(placement: .confirmationAction) { Button("Done") { focusedField = nil; dismiss() } }
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
