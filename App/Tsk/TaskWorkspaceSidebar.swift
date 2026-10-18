import SwiftUI
import TskCore

struct TaskWorkspaceSidebar: View {
    let store: TaskStore
    let openView: (TaskQuery) -> Void
    let openProject: (TaskProjectSelection) -> Void

    var body: some View {
        List {
            Section("Tasks") {
                view("Today", image: "sun.max", query: .today)
                view("Upcoming", image: "calendar", query: .upcoming)
                view("Unfinished", image: "checklist", query: .unfinished)
                view("Completed", image: "checkmark.circle", query: .completed)
            }
            Section("Projects") {
                project("All projects", selection: .all)
                project("No project", selection: .unassigned)
                ForEach(store.availableProjects.map { UTF8String($0) }) { name in
                    project(name.rawValue, selection: .project(name.rawValue))
                }
            }
            if !store.savedViews.isEmpty {
                Section("Custom views") {
                    ForEach(store.savedViews) { view in
                        Button { store.openView(view) } label: {
                            Label(view.name, systemImage: "line.3.horizontal.decrease")
                        }
                        .accessibilityIdentifier("sidebar-custom-\(view.id.uuidString)")
                        .listRowBackground(store.customView?.id == view.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("tsk")
        .accessibilityIdentifier("workspace-sidebar")
    }

    private func view(_ title: String, image: String, query: TaskQuery) -> some View {
        Button { openView(query) } label: { Label(title, systemImage: image) }
            .accessibilityIdentifier("sidebar-view-\(query.rawValue)")
            .accessibilityAddTraits(store.customView == nil && store.query == query ? .isSelected : [])
            .listRowBackground(store.customView == nil && store.query == query ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func project(_ title: String, selection: TaskProjectSelection) -> some View {
        Button { openProject(selection) } label: {
            HStack {
                Label(title, systemImage: "folder")
                if store.customView == nil && store.projectSelection == selection {
                    Spacer()
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
        }
            .accessibilityIdentifier("sidebar-project-\(title)")
            .accessibilityAddTraits(store.customView == nil && store.projectSelection == selection ? .isSelected : [])
    }
}
