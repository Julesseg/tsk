import SwiftUI
import TskCore
import TskNative

struct ShareCaptureRoot: View {
    let context: NSExtensionContext
    @State private var draft: SharedTaskDraft?
    @State private var error: String?

    var body: some View {
        Group {
            if let draft {
                ShareTaskEditor(initial: draft, cancel: cancel, complete: { context.completeRequest(returningItems: nil) })
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
        do {
            let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
            let providers = items.flatMap { $0.attachments ?? [] }
            var content = try await SharedTaskProviderLoader.load(providers)
            if content.isEmpty {
                content = items.compactMap { $0.attributedContentText?.string }.map(SharedTaskItem.text)
            }
            draft = try TaskManager.sharedDraft(from: content)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func cancel() { context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
}

private struct ShareTaskEditor: View {
    @State var draft: SharedTaskDraft
    let cancel: () -> Void
    let complete: () -> Void
    @State private var manager: TaskManager?
    @State private var error: String?
    @State private var tagInput = ""
    @State private var saving = false
    @State private var opening = false
    @FocusState private var focus: TaskEditorField?
    @FocusState private var contentFocused: Bool

    init(initial: SharedTaskDraft, cancel: @escaping () -> Void, complete: @escaping () -> Void) {
        _draft = State(initialValue: initial); self.cancel = cancel; self.complete = complete
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
        guard !opening else { return }
        opening = true
        defer { opening = false }
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
            defer { saving = false }
            do { _ = try await manager.captureSharedTask(draft); complete() }
            catch { self.error = error.localizedDescription }
        }
    }
}
