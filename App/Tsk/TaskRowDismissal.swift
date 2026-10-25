import SwiftUI
import TskCore

private struct TaskRowAvailableHeight: EnvironmentKey {
    static let defaultValue: CGFloat = 400
}

private struct TaskRowViewport: EnvironmentKey {
    static let defaultValue = CGRect.zero
}

extension EnvironmentValues {
    var taskRowAvailableHeight: CGFloat {
        get { self[TaskRowAvailableHeight.self] }
        set { self[TaskRowAvailableHeight.self] = newValue }
    }
    var taskRowViewport: CGRect {
        get { self[TaskRowViewport.self] }
        set { self[TaskRowViewport.self] = newValue }
    }
}

struct TaskRowDismissal: View {
    let bounds: CGRect
    let size: CGSize
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            target(CGRect(x: 0, y: 0, width: size.width, height: max(0, bounds.minY)))
            target(CGRect(x: 0, y: bounds.maxY, width: size.width, height: max(0, size.height - bounds.maxY)))
            target(CGRect(x: 0, y: bounds.minY, width: max(0, bounds.minX), height: bounds.height))
            target(CGRect(x: bounds.maxX, y: bounds.minY, width: max(0, size.width - bounds.maxX), height: bounds.height))
        }
    }

    private func target(_ rect: CGRect) -> some View {
        Button(action: close) { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("Save and close task")
            .accessibilityIdentifier("task-row-outside")
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

struct TaskRowActions {
    var close: () -> Void = {}
    var information: (TaskRecord) -> Void = { _ in }
}

private struct TaskRowActionsKey: EnvironmentKey {
    static var defaultValue: TaskRowActions { TaskRowActions() }
}

extension EnvironmentValues {
    var taskRowActions: TaskRowActions {
        get { self[TaskRowActionsKey.self] }
        set { self[TaskRowActionsKey.self] = newValue }
    }
}
