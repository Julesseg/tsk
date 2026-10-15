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
    private var registrations = NativeKeyboardRegistrationHistory()
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
        if let details = registrations.record(input.registrationObservation()) {
            TaskParticipantDiagnostics.event("keyboard.native-control.registrations", details: details)
        }
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

private enum NativeKeyboardRegistrationRead: Equatable {
    case notObserved(NativeKeyboardRegistrationReason)
    case observed(NativeKeyboardRegistrationValue)
}

private enum NativeKeyboardRegistrationReason: String, Codable, CaseIterable {
    case notFirstResponder, windowDetached, both
}

private struct NativeKeyboardRegistrationRow: Codable, Equatable {
    let ordinal: Int
    let owned: Bool
    let input: String
    let modifiers: UInt
    let selector: String?
    let selectorBytes: Int
    let selectorTruncated: Bool
    let priority: Bool
    let attributes: UInt
}

private struct NativeKeyboardRegistrationValue: Codable, Equatable {
    let firstResponder: Bool
    let windowAttached: Bool
    let commandNCount: Int
    let commandReturnCount: Int
    let totalReturned: Int
    let matchingN: Int
    let matchingReturn: Int
    let omittedRows: Int
    let rows: [NativeKeyboardRegistrationRow]
}

private struct NativeKeyboardRegistrationHistory {
    private struct Snapshot: Codable {
        let epoch: TimeInterval
        let processID: Int32
        let value: NativeKeyboardRegistrationValue
    }
    private struct Envelope: Codable {
        var observations: [Snapshot] = []
        var notObserved: [NativeKeyboardRegistrationReason] = []
        var omittedBySnapshotCap = 0
        var omittedByPayloadBudget = 0
        var accountingSaturated = false
    }
    private var envelope = Envelope()
    private var lastValue: NativeKeyboardRegistrationValue?
    private let counterCap = 999_999

    mutating func record(_ read: NativeKeyboardRegistrationRead, epoch: TimeInterval = Date().timeIntervalSince1970, processID: Int32 = ProcessInfo.processInfo.processIdentifier) -> [String: String]? {
        switch read {
        case .notObserved(let reason):
            guard !envelope.notObserved.contains(reason) else { return nil }
            envelope.notObserved.append(reason)
        case .observed(let value):
            let repeated = lastValue == value
            lastValue = value
            guard !repeated, !envelope.observations.contains(where: { $0.value == value }) else { return nil }
            if envelope.observations.count == 4 {
                increment(\.omittedBySnapshotCap)
            } else {
                var candidate = envelope
                candidate.observations.append(Snapshot(epoch: epoch, processID: processID, value: value))
                var reserved = candidate
                reserved.notObserved = NativeKeyboardRegistrationReason.allCases
                reserved.omittedBySnapshotCap = counterCap
                reserved.omittedByPayloadBudget = counterCap
                reserved.accountingSaturated = false
                if let data = encodedDetails(reserved), data.count <= 4096 {
                    envelope = candidate
                } else {
                    increment(\.omittedByPayloadBudget)
                }
            }
        }
        guard let details = details(envelope),
              let data = try? JSONEncoder().encode(details), data.count <= 4096 else {
            return ["registration": "omittedEncoding"]
        }
        return details
    }

    private mutating func increment(_ key: WritableKeyPath<Envelope, Int>) {
        if envelope[keyPath: key] < counterCap { envelope[keyPath: key] += 1 }
        else { envelope.accountingSaturated = true }
    }
    private func details(_ value: Envelope) -> [String: String]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return ["registration": String(decoding: data, as: UTF8.self)]
    }
    private func encodedDetails(_ value: Envelope) -> Data? {
        guard let details = details(value) else { return nil }
        return try? JSONEncoder().encode(details)
    }
}

private final class NativeKeyboardControlTextView: UITextView {
    var changed: (() -> Void)?
    private(set) var commandNCount = 0
    private(set) var commandReturnCount = 0
    private lazy var controlCommands: [UIKeyCommand] = {
        let commands = [UIKeyCommand(input: "n", modifierFlags: .command, action: #selector(commandN(_:))), UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(commandReturn(_:)))]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }()
    func registrationObservation() -> NativeKeyboardRegistrationRead {
        let focused = isFirstResponder
        let attached = window != nil
        guard focused && attached else {
            return .notObserved(!focused && !attached ? .both : (!focused ? .notFirstResponder : .windowDetached))
        }
        let returned = keyCommands ?? []
        var rows: [NativeKeyboardRegistrationRow] = []
        var matchingN = 0
        var matchingReturn = 0
        for (ordinal, command) in returned.enumerated() {
            guard command.modifierFlags == .command,
                  command.input == "n" || command.input == "\r" else { continue }
            if command.input == "n" { matchingN += 1 } else { matchingReturn += 1 }
            guard rows.count < 8 else { continue }
            let selector = NSStringFromSelector(command.action)
            let selectorBytes = Array(selector.utf8)
            rows.append(NativeKeyboardRegistrationRow(ordinal: ordinal, owned: controlCommands.contains(where: { $0 === command }), input: command.input == "n" ? "n" : "carriageReturn", modifiers: command.modifierFlags.rawValue, selector: String(decoding: selectorBytes.prefix(64), as: UTF8.self), selectorBytes: selectorBytes.count, selectorTruncated: selectorBytes.count > 64, priority: command.wantsPriorityOverSystemBehavior, attributes: command.attributes.rawValue))
        }
        return .observed(NativeKeyboardRegistrationValue(firstResponder: focused, windowAttached: attached, commandNCount: commandNCount, commandReturnCount: commandReturnCount, totalReturned: returned.count, matchingN: matchingN, matchingReturn: matchingReturn, omittedRows: matchingN + matchingReturn - rows.count, rows: rows))
    }
    override var keyCommands: [UIKeyCommand]? { (super.keyCommands ?? []) + controlCommands }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(commandN(_:)) || action == #selector(commandReturn(_:)) { return true }
        return super.canPerformAction(action, withSender: sender)
    }
    @objc private func commandN(_ sender: UIKeyCommand) { commandNCount += 1; changed?() }
    @objc private func commandReturn(_ sender: UIKeyCommand) { commandReturnCount += 1; changed?() }
}
#endif
