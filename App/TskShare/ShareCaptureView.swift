import SwiftUI
import TskCore
import TskNative

struct ShareCaptureRoot: View {
    let context: NSExtensionContext
    @State private var draft: SharedTaskDraft?
    @State private var error: String?
    let diagnosticRequest: UUID

    var body: some View {
        Group {
            if let draft {
                ShareTaskEditor(initial: draft, diagnosticRequest: diagnosticRequest, cancel: cancel, complete: finish)
            } else {
                NavigationStack {
                    Group {
                        if let error { ContentUnavailableView { Label("Cannot read shared content", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Retry") { Task { await load() } } }.accessibilityIdentifier("share-content-error") }
                        else { ProgressView("Reading shared text and links…") }
                    }
                    .navigationTitle("Add to tsk")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        TaskParticipantDiagnostics.beginShareRequest(diagnosticRequest)
        await TaskParticipantDiagnostics.$shareRequest.withValue(diagnosticRequest) { await loadContent() }
    }

    private func loadContent() async {
        do {
            let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
            let providers = items.flatMap { $0.attachments ?? [] }
            var content = try await SharedTaskProviderLoader.load(providers)
            if content.isEmpty {
                content = items.compactMap { $0.attributedContentText?.string }.map(SharedTaskItem.text)
            }
            #if DEBUG && targetEnvironment(simulator)
            for case .url(let url) in content where url.scheme == "https" && url.host == "example.com" && url.path == "/tsk-share" {
                if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "fixture" })?.value, let token = UUID(uuidString: raw) { TaskParticipantDiagnostics.enableShareFixture(token, request: diagnosticRequest) }
            }
            #endif
            draft = try TaskManager.sharedDraft(from: content)
            error = nil
        } catch {
            self.error = error.localizedDescription
            TaskParticipantDiagnostics.endShareRequest(diagnosticRequest)
        }
    }
    private func finish() {
        let trace = TaskParticipantDiagnostics.begin("share.complete-request")
        let request = diagnosticRequest
        context.completeRequest(returningItems: nil) { _ in
            TaskParticipantDiagnostics.end("share.complete-request", id: trace)
            TaskParticipantDiagnostics.endShareRequest(request)
        }
    }
    private func cancel() {
        TaskParticipantDiagnostics.endShareRequest(diagnosticRequest)
        context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

private struct ShareTaskEditor: View {
    @State var draft: SharedTaskDraft
    let diagnosticRequest: UUID
    let cancel: () -> Void
    let complete: () -> Void
    @State private var manager: TaskManager?
    @State private var error: String?
    @State private var tagInput = ""
    @State private var saving = false
    @State private var opening = false
    @FocusState private var focus: TaskEditorField?
    @FocusState private var contentFocused: Bool

    init(initial: SharedTaskDraft, diagnosticRequest: UUID, cancel: @escaping () -> Void, complete: @escaping () -> Void) {
        _draft = State(initialValue: initial); self.diagnosticRequest = diagnosticRequest; self.cancel = cancel; self.complete = complete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $draft.task.description, axis: .vertical).focused($focus, equals: .description).accessibilityIdentifier("share-task-description")
                }
                Section("Retained text and links") {
                    TextEditor(text: $draft.content).frame(minHeight: 120).focused($contentFocused).accessibilityIdentifier("share-retained-content")
                    Text("Saved as an editable task annotation. File attachments are not saved.").font(.footnote)
                }
                TaskOrganizationSection(draft: $draft.task, tagInput: $tagInput, tagError: nil, focus: $focus, addTag: { _ = addTag() })
                TaskPlanningSection(draft: $draft.task, now: Date())
                Section {
                    Text("Save stores the task on this device first. Synchronization is best effort while the extension can run and resumes when tsk opens.").font(.footnote).foregroundStyle(.secondary)
                    if manager == nil { Button(opening ? "Opening tasks…" : "Retry opening tasks") { Task { await open() } }.disabled(opening).accessibilityIdentifier("share-storage-retry") }
                }
            }
            .accessibilityIdentifier("share-task-form")
            .disabled(saving)
            .navigationTitle("Add to tsk")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("share-save-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if focus != nil || contentFocused { HStack { Spacer(); Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { focus = nil; contentFocused = false }.accessibilityIdentifier("dismiss-share-keyboard") }.padding().background(.regularMaterial) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel).disabled(saving).accessibilityIdentifier("cancel-shared-task") }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(manager == nil || saving || opening).accessibilityIdentifier("save-shared-task") }
            }
            .interactiveDismissDisabled(saving)
            .task { await open() }
        }
    }

    private func open() async {
        await TaskParticipantDiagnostics.$shareRequest.withValue(diagnosticRequest) { await openStorage() }
    }
    private func openStorage() async {
        guard !opening else { return }
        opening = true
        let trace = TaskParticipantDiagnostics.begin("share.storage-open")
        defer { opening = false; TaskParticipantDiagnostics.end("share.storage-open", id: trace) }
        do { manager = try await TaskChampionSession.open(directory: TaskChampionSession.participantDirectory()); error = nil }
        catch { manager = nil; self.error = error.localizedDescription }
    }
    private func addTag() -> Bool {
        do { try draft.task.addTag(tagInput); tagInput = ""; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func save() {
        guard let manager, !saving else { return }
        focus = nil; contentFocused = false
        if !tagInput.isEmpty, !addTag() { return }
        saving = true
        Task {
            await TaskParticipantDiagnostics.$shareRequest.withValue(diagnosticRequest) { await capture(using: manager) }
        }
    }
    private func capture(using manager: TaskManager) async {
        let trace = TaskParticipantDiagnostics.begin("share.capture")
        defer { saving = false; TaskParticipantDiagnostics.end("share.capture", id: trace) }
        do {
            let saved = try await manager.captureSharedTask(draft)
            TaskParticipantDiagnostics.event("share.capture.durable-result", details: ["id": saved.id.uuidString])
            complete()
        } catch {
            let native = error as NSError
            TaskParticipantDiagnostics.event("share.capture.error", details: ["domain": native.domain, "code": String(native.code)])
            self.error = error.localizedDescription
        }
    }
}
