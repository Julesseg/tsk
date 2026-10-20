import SwiftUI
import TskCore
import TskNative

struct ReminderImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source = EventKitReminderSource()
    @State private var lists: [ReminderList] = []
    @State private var projects: [String: String] = [:]
    @State private var preview: [ReminderImportItem]?
    @State private var result: ReminderImportResult?
    @State private var error: String?
    @State private var busy = false
    @State private var fixtureReport: String?
    @State private var isShowingTemplates = false
    @FocusState private var editingProject: Bool
    let store: TaskStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Copy incomplete reminders into new tasks. Originals stay in Apple Reminders. Repeating a copy creates additional tasks.")
                    ReminderRecurrenceInformation()
                    Button("Allow Reminders access / Refresh lists") { Task { await load(requestAccess: true) } }
                        .accessibilityIdentifier("reminders-access")
                }
                if let result {
                    Section("Copy result") {
                        Text("Copied \(result.imported.count); skipped \(result.skipped.count); failed \(result.failures.count).")
                            .accessibilityIdentifier("reminders-result")
                        ForEach(result.imported) { task in Label(task.description, systemImage: "checkmark.circle") }
                        issues(result.skipped + result.failures)
                        if result.imported.contains(where: { $0.status == "recurring" }) {
                            Button("View recurring templates") { isShowingTemplates = true }.accessibilityIdentifier("reminders-view-templates")
                        }
                        Button("View copied tasks") {
                            if store.workspaceViews.active.contains(.unfinished) { store.selectWorkspaceView(.unfinished) }
                            else { store.customView = CustomViewSelection(id: nil, name: "Copied tasks", expression: "status:pending") }
                            dismiss()
                        }.accessibilityIdentifier("reminders-view-tasks")
                    }
                } else {
                    ReminderListMappingSection(lists: lists, projects: $projects, focused: $editingProject, changed: { preview = nil })
                    Button("Preview copy") { Task { await prepare() } }
                        .disabled(projects.isEmpty).accessibilityIdentifier("reminders-preview")
                    if let preview {
                        Section("Preview") {
                            Text("\(preview.filter { $0.draft != nil }.count) eligible reminder(s)")
                                .accessibilityIdentifier("reminders-preview-count")
                            ForEach(preview.indices, id: \.self) { index in
                                let item = preview[index]
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    if item.recurrence != nil { Text("Recurring template · weekly at 09:00 GMT").accessibilityIdentifier("reminders-preview-template") }
                                    if let draft = item.draft {
                                        Text("Project: \(draft.attributes["project"] ?? "No project")")
                                        if let planned = draft.plannedDate { Text("Planned day: \(planned.formatted(date: .abbreviated, time: .shortened))") }
                                        if let deadline = draft.deadline { Text("Deadline: \(deadline.formatted(date: .abbreviated, time: .shortened))") }
                                        if let priority = draft.attributes["priority"] { Text("Priority: \(priority)") }
                                        ForEach(TaskRecord(id: UUID(), attributes: draft.attributes).annotations) { note in Text(note.text).font(.footnote) }
                                    }
                                    if let reason = item.reason { Text(reason).font(.footnote) }
                                }
                            }
                            Text("Copy rechecks the selected lists. Source changes since preview can change this result.").font(.footnote)
                            Button("Copy reminders") { Task { await copy() } }
                                .accessibilityIdentifier("reminders-copy")
                        }
                    }
                }
                if let fixtureReport {
                    Section("Isolated EventKit fixture evidence") {
                        ScrollView { Text(fixtureReport).font(.caption.monospaced()).textSelection(.enabled) }
                            .frame(height: 180)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Real EventKit fixture evidence")
                            .accessibilityValue(fixtureReport)
                            .accessibilityIdentifier("reminders-fixture-report")
                    }
                }
            }
            .accessibilityIdentifier("reminders-import-form")
            .disabled(busy)
            .overlay { if busy { ProgressView("Reading Reminders…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .safeAreaInset(edge: .top) {
                if let error { Text(error).font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("reminders-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if editingProject { HStack { Spacer(); Button("Done") { editingProject = false }.accessibilityIdentifier("dismiss-reminders-keyboard") }.padding(.horizontal).padding(.vertical, 8).background(.bar) }
            }
            .navigationTitle("Copy from Reminders")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }
        .task { await load(requestAccess: false) }
        .modifier(TaskWorkspacePanel(store: store))
        .sheet(isPresented: $isShowingTemplates) { RecurringTemplatesView(store: store) }
    }

    private func issues(_ items: [ReminderImportItem]) -> some View {
        ForEach(items.indices, id: \.self) { index in
            VStack(alignment: .leading) { Text(items[index].title).font(.headline); Text(items[index].reason ?? "Not copied").font(.footnote) }
        }
    }

    private var mappings: [ReminderListMapping] { projects.map { ReminderListMapping(listID: $0.key, project: $0.value) }.sorted { $0.listID < $1.listID } }

    private func load(requestAccess: Bool) async {
        guard !busy else { return }
        busy = true; editingProject = false
        defer { busy = false }
        do {
            if requestAccess { try await source.requestAccess() }
            #if DEBUG
            if requestAccess { fixtureReport = try await prepareReminderFixture(source: source) }
            #endif
            lists = try await source.lists()
            projects = projects.filter { id, _ in lists.contains { $0.id == id } }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func prepare() async {
        guard !busy else { return }
        busy = true; editingProject = false
        defer { busy = false }
        do { preview = try await store.manager.previewReminderImport(from: source, mappings: mappings); error = nil }
        catch { preview = nil; self.error = error.localizedDescription }
    }

    private func copy() async {
        guard !busy else { return }
        busy = true; editingProject = false
        defer { busy = false }
        do {
            result = try await store.manager.copyReminders(from: source, mappings: mappings)
            await store.reload(); error = nil
            #if DEBUG
            if let verified = try await verifyReminderFixture(source: source) { fixtureReport = (fixtureReport ?? "") + "\n" + verified }
            #endif
        } catch { self.error = error.localizedDescription }
    }
}
