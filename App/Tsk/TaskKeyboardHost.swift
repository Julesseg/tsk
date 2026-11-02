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
    private let registration = TaskKeyboardRegistration()
    private static var routers: [UUID: WeakKeyboardRouter] = [:]
    private var lastDiagnostic: String?
    private var diagnostics: [[String: Any]] = []
    #if DEBUG && targetEnvironment(simulator)
    private var recordingDiagnostic = false
    private var editingObserver: TaskKeyboardEditingObserver?
    private var editingDiagnosticCount = 0
    private var editingChanges: [ObjectIdentifier: Int] = [:]
    private var refreshCount = 0
    private var installationCount = 0
    private var removalCount = 0
    private var menuRebuildCount = 0
    #endif

    init() {
        Self.routers[id] = WeakKeyboardRouter(self)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)) != nil {
            editingObserver = TaskKeyboardEditingObserver(router: self)
        }
        #endif
    }
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
        #if DEBUG && targetEnvironment(simulator)
        refreshCount += 1
        #endif
        let declarations = commands.map { TaskKeyboardDeclaration(id: $0.id, input: $0.input, modifiers: $0.modifiers.rawValue, title: $0.title) }
        registration.reconcile(declarations, hosts: controllers.values.compactMap(\.value)) { applyRegistration() }
        diagnostic("scope changed")
    }

    private func applyRegistration() {
        for (_, (controller, keys)) in installed {
            guard let controller = controller.value else { continue }
            keys.forEach(controller.removeKeyCommand)
            #if DEBUG && targetEnvironment(simulator)
            removalCount += keys.count
            #endif
        }
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
            #if DEBUG && targetEnvironment(simulator)
            installationCount += keys.count
            #endif
            installed[identity] = (WeakKeyboardController(controller), keys)
        }
        UIMenuSystem.main.setNeedsRebuild()
        #if DEBUG && targetEnvironment(simulator)
        menuRebuildCount += 1
        #endif
    }

    static func perform(_ key: UIKeyCommand) {
        let activeRouters = routers.values.compactMap(\.value)
        let input = key.input ?? "nil"
        let metadata = String(describing: key.propertyList)
        activeRouters.forEach { $0.diagnostic("selector entry input=\(input) modifiers=\(key.modifierFlags.rawValue) propertyList=\(metadata)") }
        guard let identity = key.propertyList as? [String: String] else {
            activeRouters.forEach { $0.diagnostic("selector dropped invalid propertyList") }
            return
        }
        guard let id = identity["router"].flatMap(UUID.init(uuidString:)), let router = routers[id]?.value else {
            activeRouters.forEach { $0.diagnostic("selector dropped unknown router=\(identity["router"] ?? "nil")") }
            return
        }
        guard let command = router.commands.first(where: { $0.id == identity["command"] && $0.input == key.input && $0.modifiers == key.modifierFlags }) else {
            router.diagnostic("selector dropped inactive command=\(identity["command"] ?? "nil") input=\(input) modifiers=\(key.modifierFlags.rawValue)")
            return
        }
        router.diagnostic("execute " + command.id)
        command.action()
    }

    func diagnostic(_ event: String, force: Bool = false) {
        #if DEBUG && targetEnvironment(simulator)
        guard let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: token) != nil, !recordingDiagnostic else { return }
        recordingDiagnostic = true
        defer { recordingDiagnostic = false }
        let hosts = controllers.values.compactMap(\.value).map { String(describing: type(of: $0)) }
        let text = event + " scopes=" + commands.map(\.id).joined(separator: ",") + " hosts=" + hosts.joined(separator: ",")
        guard force || lastDiagnostic != text else { return }
        lastDiagnostic = text
        var chain: [String] = []
        let capture = TaskFirstResponderCapture()
        let captured = UIApplication.shared.sendAction(#selector(UIResponder.tskCaptureFirstResponder(_:)), to: nil, from: capture, for: nil)
        var responder = capture.responder
        var runtimeCommands: [[String: Any]] = []
        while let current = responder, chain.count < 30 {
            let name = String(describing: type(of: current))
            chain.append(name)
            runtimeCommands.append(["responder": name, "firstResponder": current.isFirstResponder, "returnCommands": diagnosticReturnCommands(current)])
            responder = current.next
        }
        let declarations = installed.values.compactMap { controller, keys -> [String: Any]? in
            guard let controller = controller.value else { return nil }
            var ancestors: [String] = []
            var parent = controller.parent
            while let current = parent, ancestors.count < 15 { ancestors.append(String(describing: type(of: current))); parent = current.parent }
            return ["controller": String(describing: type(of: controller)), "firstResponder": controller.isFirstResponder,
                    "windowAttached": controller.viewIfLoaded?.window != nil, "parents": ancestors,
                    "runtimeReturnCommands": diagnosticReturnCommands(controller),
                    "presenting": controller.presentingViewController.map { String(describing: type(of: $0)) } ?? "nil",
                    "inputs": keys.map { ["input": $0.input ?? "nil", "modifiers": $0.modifierFlags.rawValue, "action": $0.action.map { NSStringFromSelector($0) } ?? "nil"] as [String: Any] }]
        }
        var directChains: [[String: Any]] = []
        var windows = Set<ObjectIdentifier>()
        for controller in controllers.values.compactMap(\.value) {
            guard let window = controller.viewIfLoaded?.window, windows.insert(ObjectIdentifier(window)).inserted else { continue }
            var current = window.tskFirstResponder ?? controllers.values.compactMap(\.value).first { $0.isFirstResponder && $0.viewIfLoaded?.window === window }
            var values: [[String: Any]] = []
            while let responder = current, values.count < 30 {
                values.append(["responder": String(describing: type(of: responder)), "firstResponder": responder.isFirstResponder,
                               "returnCommands": diagnosticReturnCommands(responder)])
                current = responder.next
            }
            directChains.append(["keyWindow": window.isKeyWindow, "chain": values])
        }
        diagnostics.append(["time": Date().timeIntervalSince1970, "event": text, "responderCaptureDelivered": captured, "responderChain": chain, "runtimeCommands": runtimeCommands, "declarations": declarations,
                            "directWindowResponders": directChains, "refreshCount": refreshCount, "installationCount": installationCount,
                            "removalCount": removalCount, "menuRebuildCount": menuRebuildCount])
        diagnostics = Array(diagnostics.suffix(80))
        NSLog("tsk keyboard %@ chain=%@", text, chain.joined(separator: ">"))
        if let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: token) != nil {
            do {
                let data = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-fixture-\(token)-\(ProcessInfo.processInfo.processIdentifier).json")
                try data.write(to: file, options: .atomic)
            } catch { NSLog("tsk owned keyboard diagnostic failed: %@", error.localizedDescription) }
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    fileprivate func editingNotification(_ notification: Notification) {
        guard editingDiagnosticCount < 32, let view = notification.object as? UIView, let window = view.window,
              controllers.values.contains(where: { $0.value?.viewIfLoaded?.window === window }) else { return }
        let identity = ObjectIdentifier(view)
        let changed = notification.name == UITextView.textDidChangeNotification || notification.name == UITextField.textDidChangeNotification
        if changed {
            guard editingChanges[identity, default: 0] < 4 else { return }
            editingChanges[identity, default: 0] += 1
        } else { editingChanges[identity] = 0 }
        editingDiagnosticCount += 1
        diagnostic("editing notification=\(notification.name.rawValue) view=\(String(describing: type(of: view))) firstResponder=\(view.isFirstResponder)", force: true)
    }

    private func diagnosticReturnCommands(_ responder: UIResponder) -> [[String: Any]] {
        (responder.keyCommands ?? []).filter { $0.input == "\r" && $0.modifierFlags.contains(.command) }.map { command in
            var record: [String: Any] = ["input": command.input ?? "nil", "modifiers": command.modifierFlags.rawValue,
                "action": command.action.map { NSStringFromSelector($0) } ?? "nil",
                "wantsPriorityOverSystemBehavior": command.wantsPriorityOverSystemBehavior,
                "attributes": command.attributes.rawValue]
            if let action = command.action {
                record["canPerformAction"] = responder.canPerformAction(action, withSender: command)
                record["target"] = responder.target(forAction: action, withSender: command).map { String(describing: type(of: $0)) } ?? "nil"
            }
            return record
        }
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private final class TaskKeyboardEditingObserver: NSObject {
    private weak var router: TaskKeyboardRouter?

    @MainActor init(router: TaskKeyboardRouter) {
        self.router = router
        super.init()
        for name in [UITextView.textDidBeginEditingNotification, UITextView.textDidChangeNotification, UITextView.textDidEndEditingNotification,
                     UITextField.textDidBeginEditingNotification, UITextField.textDidChangeNotification, UITextField.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(observed(_:)), name: name, object: nil)
        }
    }

    @objc private func observed(_ notification: Notification) {
        router?.editingNotification(notification)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
#endif

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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.key?.modifierFlags.contains(.command) == true {
            router.diagnostic("command press code=\(press.key?.keyCode.rawValue ?? 0)")
        }
        super.pressesBegan(presses, with: event)
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

private final class TaskFirstResponderCapture: NSObject {
    weak var responder: UIResponder?
}

private extension UIResponder {
    @objc func tskCaptureFirstResponder(_ sender: Any?) {
        (sender as? TaskFirstResponderCapture)?.responder = self
    }
}

private extension UIView {
    var tskFirstResponder: UIResponder? {
        if isFirstResponder { return self }
        for child in subviews { if let responder = child.tskFirstResponder { return responder } }
        return nil
    }
}
