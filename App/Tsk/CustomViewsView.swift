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
    func loadSavedViews() async throws { savedViews = try await manager.savedViews() }

    func openView(_ view: SavedTaskView) {
        customView = CustomViewSelection(id: view.id, name: view.name, expression: view.expression)
    }
}

struct CustomViewsView: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ViewEditorRoute?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("saved-view-error") }
                if store.savedViews.isEmpty {
                    Text("Save a Taskwarrior filter to reopen its task view on this device.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.savedViews) { view in
                    Button {
                        store.openView(view)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(view.name)
                            Text(view.expression.isEmpty ? "All tasks" : view.expression)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("saved-view-\(view.id.uuidString)")
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await remove(view) } }
                        Button("Edit") { editing = ViewEditorRoute(view: view) }.tint(.blue)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = ViewEditorRoute(view: view) }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await remove(view) } }
                    }
                }
            }
            .navigationTitle("Custom views")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
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
    }

    private func remove(_ view: SavedTaskView) async {
        do {
            try await store.manager.deleteView(id: view.id)
            try await store.loadSavedViews()
            if store.customView?.id == view.id { store.customView = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ViewEditorRoute: Identifiable {
    let id = UUID()
    let view: SavedTaskView?
}
