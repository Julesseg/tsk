#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit
import TskNative

enum NativeKeyboardControlGate {
    static func enabled(_ environment: [String: String]) -> Bool {
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let token = environment["TSK_TEST_NATIVE_KEYBOARD_CONTROL"].flatMap(UUID.init(uuidString:)),
              let replica = environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)) else { return false }
        return token == replica
    }
}

struct NativeKeyboardControlView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NativeKeyboardControlController { NativeKeyboardControlController() }
    func updateUIViewController(_ controller: NativeKeyboardControlController, context: Context) {}
}

final class NativeKeyboardControlController: UIViewController, UITextViewDelegate {
    private let input = NativeKeyboardControlTextView()
    private let status = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        input.accessibilityIdentifier = "native-keyboard-control-input"
        input.font = .preferredFont(forTextStyle: .body)
        input.autocapitalizationType = .none
        input.backgroundColor = .secondarySystemBackground
        input.delegate = self
        input.changed = { [weak self] in self?.publish() }
        status.numberOfLines = 0
        status.accessibilityIdentifier = "native-keyboard-control-status"
        let stack = UIStackView(arrangedSubviews: [status, input])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20), input.heightAnchor.constraint(equalToConstant: 180)])
        publish()
    }
    func textViewDidBeginEditing(_ textView: UITextView) { publish() }
    func textViewDidChange(_ textView: UITextView) { publish() }
    private func publish() {
        let value = NativeKeyboardControlStatus(processID: ProcessInfo.processInfo.processIdentifier, firstResponder: input.isFirstResponder, textLength: input.text.count, textIsPlainN: input.text == "n", commandNCount: input.commandNCount, commandReturnCount: input.commandReturnCount)
        status.text = "Native keyboard control · n: \(value.commandNCount) · Return: \(value.commandReturnCount) · input length: \(value.textLength)"
        status.accessibilityValue = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
        TaskParticipantDiagnostics.event("keyboard.native-control.state", details: ["firstResponder": String(value.firstResponder), "textLength": String(value.textLength), "textIsPlainN": String(value.textIsPlainN), "commandNCount": String(value.commandNCount), "commandReturnCount": String(value.commandReturnCount)])
    }
}

private struct NativeKeyboardControlStatus: Encodable {
    let processID: Int32
    let firstResponder: Bool
    let textLength: Int
    let textIsPlainN: Bool
    let commandNCount: Int
    let commandReturnCount: Int
}

private final class NativeKeyboardControlTextView: UITextView {
    var changed: (() -> Void)?
    private(set) var commandNCount = 0
    private(set) var commandReturnCount = 0
    private lazy var controlCommands: [UIKeyCommand] = {
        let commands = [UIKeyCommand(input: "n", modifierFlags: .command, action: #selector(commandN)), UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(commandReturn))]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }()
    override var keyCommands: [UIKeyCommand]? { (super.keyCommands ?? []) + controlCommands }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(commandN) || action == #selector(commandReturn) { return true }
        return super.canPerformAction(action, withSender: sender)
    }
    @objc private func commandN() { commandNCount += 1; changed?() }
    @objc private func commandReturn() { commandReturnCount += 1; changed?() }
}
#endif
