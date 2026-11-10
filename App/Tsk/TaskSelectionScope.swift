import SwiftUI
import UIKit

@MainActor final class TaskSelectionScope {
    weak var list: UIScrollView?
    weak var selectionRecognizer: UIGestureRecognizer?
}

struct TaskRowTapTarget: UIViewRepresentable {
    let scope: TaskSelectionScope?
    let isEnabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> TaskRowTapView { TaskRowTapView() }

    func updateUIView(_ view: TaskRowTapView, context: Context) {
        view.scope = scope
        view.action = action
        view.tap.isEnabled = isEnabled
    }
}

final class TaskRowTapView: UIView, UIGestureRecognizerDelegate {
    weak var scope: TaskSelectionScope?
    var action: (() -> Void)?
    let tap = UITapGestureRecognizer()

    init() {
        super.init(frame: .zero)
        tap.delegate = self
        tap.addTarget(self, action: #selector(activate))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func activate() { action?() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        other === scope?.selectionRecognizer
    }
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
