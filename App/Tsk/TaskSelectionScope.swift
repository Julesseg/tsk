import SwiftUI
import UIKit

@MainActor final class TaskSelectionScope {
    weak var list: UIScrollView?
}

private struct TaskSelectionScopeKey: EnvironmentKey {
    static let defaultValue: TaskSelectionScope? = nil
}

extension EnvironmentValues {
    var taskSelectionScope: TaskSelectionScope? {
        get { self[TaskSelectionScopeKey.self] }
        set { self[TaskSelectionScopeKey.self] = newValue }
    }
}

struct TaskSelectionRowAnchor: UIViewRepresentable {
    @Environment(\.taskSelectionScope) private var scope

    func makeUIView(context: Context) -> TaskSelectionRowView {
        let view = TaskSelectionRowView()
        view.scope = scope
        return view
    }

    func updateUIView(_ view: TaskSelectionRowView, context: Context) {
        view.scope = scope
        view.resolveList()
    }
}

final class TaskSelectionRowView: UIView {
    weak var scope: TaskSelectionScope?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveList()
    }

    func resolveList() {
        guard window != nil else { return }
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scope?.list = scroll
                return
            }
            ancestor = current.superview
        }
    }
}
