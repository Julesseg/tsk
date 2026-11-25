import SwiftUI
import TskCore

struct TaskWorkspaceFooter: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    let controls: TaskWorkspaceControls?
    var openPlannerDay: ((Date) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            TaskDayNavigator(store: store, paging: paging, availableWidth: availableWidth, openPlannerDay: openPlannerDay)
            if !paging.isCalendarVisible { controls }
        }
    }
}

struct TaskWorkspaceControls: View {
    let workspace: Binding<WorkspaceView>?
    let capture: () -> Void

    var body: some View {
        HStack {
            if let workspace {
                Menu {
                    Picker("Workspace", selection: workspace) {
                        Label("Planner", systemImage: "calendar").tag(WorkspaceView.today)
                            .accessibilityIdentifier("open-today")
                        Label("Inbox", systemImage: "tray").tag(WorkspaceView.inbox)
                            .accessibilityIdentifier("open-inbox")
                        Label("Projects", systemImage: "folder").tag(WorkspaceView.projects)
                            .accessibilityIdentifier("open-projects")
                    }
                    .pickerStyle(.inline)
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
