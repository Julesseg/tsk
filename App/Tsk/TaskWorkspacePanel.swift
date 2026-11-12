import SwiftUI

struct TaskWorkspacePanel: ViewModifier {
    @Environment(TaskURLController.self) private var automation
    let store: TaskStore
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .modifier(TaskActionMessage(controller: automation))
            .onAppear { store.presentedTaskPanels.insert(id) }
            .onDisappear { store.presentedTaskPanels.remove(id) }
    }
}
