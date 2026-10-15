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
    private let id = UUID()
    private var controllers: [UUID: WeakKeyboardController] = [:]
    private var installed: [ObjectIdentifier: (WeakKeyboardController, [UIKeyCommand])] = [:]
    private static var routers: [UUID: WeakKeyboardRouter] = [:]
    private var lastDiagnostic: String?
    private var diagnostics: [[String: Any]] = []

    init() { Self.routers[id] = WeakKeyboardRouter(self) }
    var commands: [TaskKeyboardCommand] { order.last.flatMap { scopes[$0] } ?? [] }

    func set(_ commands: [TaskKeyboardCommand], for id: UUID, controller: UIViewController) {
        if scopes[id] == nil { order.append(id) }
        scopes[id] = commands
        controllers[id] = WeakKeyboardController(controller)
        refresh()
    }

    func remove(_ id: UUID) {
        scopes.removeValue(forKey: id)
        order.removeAll { $0 == id }
        controllers.removeValue(forKey: id)
        refresh()
    }
    private func refresh() {
        for (_, (controller, keys)) in installed { keys.forEach { controller.value?.removeKeyCommand($0) } }
        installed.removeAll()
        for controller in controllers.values.compactMap(\.value) {
            let identity = ObjectIdentifier(controller)
            guard installed[identity] == nil else { continue }
            let keys = commands.map { command in
                let key = UIKeyCommand(title: command.title ?? "", action: #selector(UIViewController.tskPerformScopedTaskCommand(_:)), input: command.input, modifierFlags: command.modifiers, propertyList: ["router": id.uuidString, "command": command.id])
                key.discoverabilityTitle = command.title
                key.wantsPriorityOverSystemBehavior = true
                return key
            }
            keys.forEach(controller.addKeyCommand)
            installed[identity] = (WeakKeyboardController(controller), keys)
        }
        UIMenuSystem.main.setNeedsRebuild()
        diagnostic("scope changed")
    }

    static func perform(_ key: UIKeyCommand) {
        guard let identity = key.propertyList as? [String: String], let id = identity["router"].flatMap(UUID.init(uuidString:)), let router = routers[id]?.value,
              let command = router.commands.first(where: { $0.id == identity["command"] && $0.input == key.input && $0.modifiers == key.modifierFlags }) else { return }
        router.diagnostic("execute " + command.id)
        command.action()
    }

    func diagnostic(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"] != nil else { return }
        let hosts = controllers.values.compactMap(\.value).map { String(describing: type(of: $0)) }
        let text = event + " scopes=" + commands.map(\.id).joined(separator: ",") + " hosts=" + hosts.joined(separator: ",")
        guard lastDiagnostic != text else { return }
        lastDiagnostic = text
        var chain: [String] = []
        var responder = controllers.values.compactMap(\.value).first?.view.window?.tskFirstResponder
        while let current = responder, chain.count < 30 { chain.append(String(describing: type(of: current))); responder = current.next }
        diagnostics.append(["time": Date().timeIntervalSince1970, "event": text, "responderChain": chain])
        diagnostics = Array(diagnostics.suffix(80))
        NSLog("tsk keyboard %@ chain=%@", text, chain.joined(separator: ">"))
        if let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: token) != nil {
            do {
                let data = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-fixture-\(token).json")
                try data.write(to: file, options: .atomic)
            } catch { NSLog("tsk owned keyboard diagnostic failed: %@", error.localizedDescription) }
        }
        #endif
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentedViewController == nil, !(view.window?.tskFirstResponder is any UITextInput) { becomeFirstResponder() }
        router.diagnostic("workspace appeared firstResponder=\(isFirstResponder)")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIViewController.tskPerformScopedTaskCommand(_:)) {
            router.diagnostic("availability sender=\(sender.map { String(describing: type(of: $0)) } ?? "nil")")
            return !router.commands.isEmpty
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

private final class WeakKeyboardController {
    weak var value: UIViewController?
    init(_ value: UIViewController) { self.value = value }
}

private final class WeakKeyboardRouter {
    weak var value: TaskKeyboardRouter?
    init(_ value: TaskKeyboardRouter) { self.value = value }
}

extension UIViewController {
    @objc fileprivate func tskPerformScopedTaskCommand(_ command: UIKeyCommand) {
        TaskKeyboardRouter.perform(command)
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
            if window == nil { router?.remove(id) }
            else {
                register()
                DispatchQueue.main.async { [weak self] in self?.register() }
            }
        }

        func register() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let controller = next as? UIViewController {
                    router?.set(commands, for: id, controller: controller)
                    return
                }
                responder = next
            }
        }
    }
}

extension View {
    func taskKeyboardCommands(_ commands: [TaskKeyboardCommand]) -> some View {
        background(TaskKeyboardScope(commands: commands).allowsHitTesting(false))
    }
}

private extension UIView {
    var tskFirstResponder: UIResponder? {
        if isFirstResponder { return self }
        for child in subviews { if let responder = child.tskFirstResponder { return responder } }
        return nil
    }
}
