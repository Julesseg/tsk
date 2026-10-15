import SwiftUI
import UIKit

struct TaskKeyboardCommand {
    let id: String
    let input: String
    let modifiers: UIKeyModifierFlags
    let title: String?
    let action: () -> Void

    static var suspended: [TaskKeyboardCommand] {
        [TaskKeyboardCommand(id: "suspended-capture", input: "n", modifiers: .command, title: nil, action: {})]
    }
}

@MainActor
final class TaskKeyboardRouter {
    private var order: [UUID] = []
    private var scopes: [UUID: [TaskKeyboardCommand]] = [:]
    var changed: (() -> Void)?
    var commands: [TaskKeyboardCommand] { order.last.flatMap { scopes[$0] } ?? [] }

    func set(_ commands: [TaskKeyboardCommand], for id: UUID) {
        if scopes[id] == nil { order.append(id) }
        scopes[id] = commands
        changed?()
    }

    func remove(_ id: UUID) {
        scopes.removeValue(forKey: id)
        order.removeAll { $0 == id }
        changed?()
    }
}

private struct TaskKeyboardRouterKey: EnvironmentKey {
    static let defaultValue: TaskKeyboardRouter? = nil
}

extension EnvironmentValues {
    var taskKeyboardRouter: TaskKeyboardRouter? {
        get { self[TaskKeyboardRouterKey.self] }
        set { self[TaskKeyboardRouterKey.self] = newValue }
    }
}

struct TaskKeyboardHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> TaskKeyboardController {
        let controller = TaskKeyboardController(rootView: AnyView(EmptyView()))
        controller.rootView = AnyView(content().environment(\.taskKeyboardRouter, controller.router))
        return controller
    }

    func updateUIViewController(_ controller: TaskKeyboardController, context: Context) {
        controller.rootView = AnyView(content().environment(\.taskKeyboardRouter, controller.router))
    }
}

final class TaskKeyboardController: UIHostingController<AnyView> {
    let router = TaskKeyboardRouter()
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        router.changed = { UIMenuSystem.main.setNeedsRebuild() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentedViewController == nil { becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        router.commands.map { command in
            let key: UIKeyCommand
            if let title = command.title {
                key = UIKeyCommand(title: title, action: #selector(performTaskCommand(_:)), input: command.input, modifierFlags: command.modifiers, propertyList: command.id)
                key.discoverabilityTitle = title
            } else {
                key = UIKeyCommand(input: command.input, modifierFlags: command.modifiers, action: #selector(performTaskCommand(_:)))
            }
            key.wantsPriorityOverSystemBehavior = true
            return key
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(performTaskCommand(_:)) {
            guard let key = sender as? UIKeyCommand else { return false }
            return router.commands.contains { $0.input == key.input && $0.modifiers == key.modifierFlags }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func performTaskCommand(_ command: UIKeyCommand) {
        router.commands.first { $0.input == command.input && $0.modifiers == command.modifierFlags }?.action()
    }
}

private struct TaskKeyboardScope: UIViewRepresentable {
    @Environment(\.taskKeyboardRouter) private var router
    let commands: [TaskKeyboardCommand]

    func makeUIView(context: Context) -> ScopeView { ScopeView() }

    func updateUIView(_ view: ScopeView, context: Context) {
        view.router = router
        view.commands = commands
        view.register()
    }

    static func dismantleUIView(_ view: ScopeView, coordinator: ()) { view.router?.remove(view.id) }

    final class ScopeView: UIView {
        let id = UUID()
        weak var router: TaskKeyboardRouter?
        var commands: [TaskKeyboardCommand] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { router?.remove(id) } else { register() }
        }

        func register() {
            if window != nil { router?.set(commands, for: id) }
        }
    }
}

extension View {
    func taskKeyboardCommands(_ commands: [TaskKeyboardCommand]) -> some View {
        background(TaskKeyboardScope(commands: commands).allowsHitTesting(false))
    }
}
