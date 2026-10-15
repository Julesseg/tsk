import SwiftUI
import TskCore

struct TaskWorkspaceSidebar: View {
    let store: TaskStore
    let openView: (TaskQuery) -> Void
    let openProject: (TaskProjectSelection) -> Void
    let customViews: () -> Void
    let synchronization: () -> Void
    let shortcuts: () -> Void
    let recurring: () -> Void
    let attributeDefinitions: () -> Void
    let reminders: () -> Void
    let continuousReminders: () -> Void
    let spotlight: () -> Void
                Button("Task notifications", systemImage: "bell", action: notifications).accessibilityIdentifier("notification-settings")
                Button("Move from Reminders automatically", systemImage: "arrow.down.forward.circle", action: continuousReminders)
                    .accessibilityIdentifier("continuous-reminders-settings")
                Button("Copy from Reminders", systemImage: "square.and.arrow.down", action: reminders)
                    .accessibilityIdentifier("reminders-import")
                Button("Recurring templates", systemImage: "repeat", action: recurring).accessibilityIdentifier("recurring-templates")
                Button("Attribute definitions", systemImage: "slider.horizontal.3", action: attributeDefinitions)
                    .accessibilityIdentifier("attribute-definitions")
                Button("Synchronization", systemImage: "arrow.triangle.2.circlepath", action: synchronization)
                    .accessibilityIdentifier("synchronization-settings")
                Button("Shortcuts and Siri", systemImage: "square.stack.3d.up", action: shortcuts)
                    .accessibilityIdentifier("task-shortcuts")
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
