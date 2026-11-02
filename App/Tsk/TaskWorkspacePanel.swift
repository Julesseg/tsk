import SwiftUI

struct TaskWorkspacePanel: ViewModifier {
    let store: TaskStore
    var nativeTraceScope: String? = nil
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                store.presentedTaskPanels.insert(id)
                TaskNativeInteractionTrace.panel(nativeTraceScope, id: id, active: true)
            }
            .onDisappear {
                store.presentedTaskPanels.remove(id)
                TaskNativeInteractionTrace.panel(nativeTraceScope, id: id, active: false)
            }
    }
}
