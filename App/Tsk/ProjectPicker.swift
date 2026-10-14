import SwiftUI
import TskCore

struct ProjectPicker: View {
    let store: TaskStore

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("Project", selection: $store.projectSelection) {
                Text("All projects").tag(TaskProjectSelection.all)
                Text("Without a project").tag(TaskProjectSelection.unassigned)
                ForEach(projects.map { UTF8String($0) }) { project in
                    Text(project.rawValue).tag(TaskProjectSelection.project(project.rawValue))
                }
            }
        } label: {
            Label(title, systemImage: "folder")
        }
        .accessibilityIdentifier("project-filter")
    }

    private var projects: [String] {
        Array(Set((store.availableProjects + [store.projectSelection.projectName].compactMap { $0 }).map { UTF8String($0) })).sorted().map(\.rawValue)
    }

    private var title: String {
        switch store.projectSelection {
        case .all: "All projects"
        case .unassigned: "Without a project"
        case .project(let name): name
        }
    }
}
