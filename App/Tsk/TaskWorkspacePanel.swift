import SwiftUI

struct TaskWorkspacePanel: ViewModifier {
    let store: TaskStore
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { store.presentedTaskPanels.insert(id) }
            .onDisappear { store.presentedTaskPanels.remove(id) }
    }
}
