import SwiftUI
import TskCore

struct TaskWorkspaceControls: View {
    let workspace: Binding<WorkspaceView>?
    let capture: () -> Void

    var body: some View {
        HStack {
            if let workspace {
                Menu {
                    Button("Planner", systemImage: "calendar") { workspace.wrappedValue = .today }
                        .accessibilityIdentifier("open-today")
                    Button("Inbox", systemImage: "tray") { workspace.wrappedValue = .inbox }
                        .accessibilityIdentifier("open-inbox")
                    Button("Projects", systemImage: "folder") { workspace.wrappedValue = .projects }
                        .accessibilityIdentifier("open-projects")
                } label: {
                    circle("line.3.horizontal")
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Workspace menu")
                .accessibilityValue(workspace.wrappedValue == .today ? "Planner" : workspace.wrappedValue.title)
                .accessibilityIdentifier("workspace-menu")
            }
            Spacer()
            Button(action: capture) { circle("plus") }
                .accessibilityLabel("New task")
                .accessibilityIdentifier("new-task")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, TaskDayPaging.verticalPadding)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .frame(width: TaskDayPaging.pillHeight, height: TaskDayPaging.pillHeight)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
    }
}
