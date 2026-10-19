import SwiftUI
import TskCore

struct CustomViewSelection: Equatable {
    let id: UUID?
    let name: String
    let expression: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name.matchesBytes(rhs.name) && lhs.expression.matchesBytes(rhs.expression)
    }
}

extension TaskStore {
    func loadSavedViews() async throws {
        savedViews = try await manager.savedViews()
        try loadWorkspaceViews()
    }

    func openView(_ view: SavedTaskView) {
        customView = CustomViewSelection(id: view.id, name: view.name, expression: view.expression)
    }
}

struct CustomViewsView: View {
    let store: TaskStore
    let select: (WorkspaceView) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ViewEditorRoute?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("saved-view-error") }
                Section {
                    ForEach(store.workspaceViews.active) { view in
                        viewRow(view, active: true)
                    }
                    .onMove { from, to in update { $0.moveActive(from: from, to: to) } }
                } header: {
                    Text("Active · \(store.workspaceViews.active.count) of \(WorkspaceViews.maximumActive)")
                } footer: {
                    Text("Drag to reorder the tabs. The first view opens when you launch tsk. Keep at least one active view.")
                }
                Section {
                    ForEach(store.workspaceViews.inactive) { view in
                        viewRow(view, active: false)
                    }
                    .onMove { from, to in update { $0.moveInactive(from: from, to: to) } }
                } header: {
                    Text("Other views")
                } footer: {
                    Text("Add up to four active views. Use a custom view’s options to edit or delete its filter.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .accessibilityIdentifier("views-list")
            .navigationTitle("Views")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-views") }
                ToolbarItem(placement: .primaryAction) {
                    Button("New view", systemImage: "plus") { editing = ViewEditorRoute(view: nil) }
                        .accessibilityIdentifier("new-custom-view")
                }
            }
            .sheet(item: $editing) { route in
                RawFilterEditorView(store: store, original: route.view) { dismiss() }
            }
            .task {
                do { try await store.loadSavedViews(); error = nil }
                catch { self.error = error.localizedDescription }
            }
        }
        .tint(.primary)
    }

    private func viewRow(_ view: WorkspaceView, active: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                update {
                    if active { try $0.deactivate(view) }
                    else { try $0.activate(view) }
                }
            } label: {
                Image(systemName: active ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(active ? Color.red : Color.green)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(active ? store.workspaceViews.active.count == 1 : store.workspaceViews.active.count == WorkspaceViews.maximumActive)
            .accessibilityLabel((active ? "Remove " : "Add ") + view.title(in: store))
            .accessibilityIdentifier((active ? "deactivate-" : "activate-") + view.id)
            Button {
                if active {
                    select(view)
                    dismiss()
                } else if case .custom(let id) = view, let saved = store.savedViews.first(where: { $0.id == id }) {
                    editing = ViewEditorRoute(view: saved)
                }
            } label: {
                Label(view.title(in: store), systemImage: view.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(rowIdentifier(view))
            if case .custom(let id) = view, let saved = store.savedViews.first(where: { $0.id == id }) {
                Menu("View options", systemImage: "ellipsis") {
                    Button("Edit", systemImage: "pencil") { editing = ViewEditorRoute(view: saved) }
                    Button("Delete", systemImage: "trash", role: .destructive) { Task { await remove(saved) } }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Options for " + view.title(in: store))
                .accessibilityIdentifier("view-options-" + id.uuidString)
            }
        }
        .deleteDisabled(true)
        .accessibilityAction(named: "Move to first") {
            update {
                let rows = active ? $0.active : $0.inactive
                if let index = rows.firstIndex(of: view) {
                    if active { $0.moveActive(from: IndexSet(integer: index), to: 0) }
                    else { $0.moveInactive(from: IndexSet(integer: index), to: 0) }
                }
            }
        }
    }

    private func rowIdentifier(_ view: WorkspaceView) -> String {
        if case .custom(let id) = view { return "saved-view-" + id.uuidString }
        return "view-" + view.id
    }

    private func update(_ change: (inout WorkspaceViews) throws -> Void) {
        do { try store.updateWorkspaceViews(change); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ view: SavedTaskView) async {
        do {
            try await store.manager.deleteView(id: view.id)
            try await store.loadSavedViews()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ViewEditorRoute: Identifiable {
    let id = UUID()
    let view: SavedTaskView?
}
