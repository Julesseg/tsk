import SwiftUI
import UIKit
import TskCore

struct TaskMenuFocusDismissal: UIViewRepresentable {
    @FocusState.Binding var titleFocused: Bool
    @FocusState.Binding var focusedNote: UTF8String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.activate = { control, generation in
            #if DEBUG && targetEnvironment(simulator)
            let beforeTitle = titleFocused
            let beforeNote = focusedNote?.rawValue ?? "nil"
            #endif
            titleFocused = false
            focusedNote = nil
            #if DEBUG && targetEnvironment(simulator)
            TaskMenuFocusDiagnostics.record("activation", details: [
                "control": String(describing: ObjectIdentifier(control)), "generation": String(generation),
                "titleBefore": String(beforeTitle), "noteBefore": beforeNote,
                "titleAfter": String(titleFocused), "noteAfter": focusedNote?.rawValue ?? "nil"
            ])
            #endif
        }
        view.refresh()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        coordinator.detach()
        coordinator.activate = nil
        view.coordinator = nil
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        private var deferredAttachment = false

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            refresh()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            deferredAttachment = false
            refresh()
        }

        func refresh() {
            coordinator?.attach(to: self)
            guard window != nil, !deferredAttachment else { return }
            deferredAttachment = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                coordinator?.attach(to: self)
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var activate: ((UIControl, Int) -> Void)?
        private weak var control: UIControl?
        private weak var anchor: Anchor?
        private var generation = 0
        private var lastCoverage: String?

        func attach(to anchor: Anchor) {
            self.anchor = anchor
            var current = anchor.superview
            var candidate: UIControl?
            var ancestry: [String] = []
            while let view = current, ancestry.count < 16, let window = anchor.window, view.window === window {
                ancestry.append(String(describing: ObjectIdentifier(view)))
                if let source = view as? UIControl { candidate = source; break }
                if view === window { break }
                current = view.superview
            }
            if control !== candidate {
                detach()
                self.anchor = anchor
                control = candidate
                generation += 1
                candidate?.addTarget(self, action: #selector(menuActivated(_:)), for: .menuActionTriggered)
            }
            #if DEBUG && targetEnvironment(simulator)
            let coverage = ancestry.joined(separator: ",") + "|" + String(anchor.window != nil)
            if coverage != lastCoverage {
                lastCoverage = coverage
                TaskMenuFocusDiagnostics.record("attachment", details: [
                    "anchor": String(describing: ObjectIdentifier(anchor)),
                    "control": candidate.map { String(describing: ObjectIdentifier($0)) } ?? "unavailable",
                    "controlClass": candidate.map { NSStringFromClass(type(of: $0)) } ?? "unavailable",
                    "coordinator": String(describing: ObjectIdentifier(self)), "generation": String(generation),
                    "windowAttached": String(anchor.window != nil), "ancestry": ancestry.joined(separator: ","),
                    "ancestryLimitReached": String(ancestry.count == 16)
                ])
            }
            #endif
        }

        func detach() {
            guard let control else { return }
            control.removeTarget(self, action: #selector(menuActivated(_:)), for: .menuActionTriggered)
            #if DEBUG && targetEnvironment(simulator)
            TaskMenuFocusDiagnostics.record("detachment", details: [
                "control": String(describing: ObjectIdentifier(control)), "generation": String(generation),
                "coordinator": String(describing: ObjectIdentifier(self))
            ])
            #endif
            self.control = nil
        }

        @objc private func menuActivated(_ sender: UIControl) {
            let valid = sender === control && anchor?.window != nil && sender.window === anchor?.window
                && anchor?.isDescendant(of: sender) == true
            #if DEBUG && targetEnvironment(simulator)
            TaskMenuFocusDiagnostics.record("delivery", details: [
                "sender": String(describing: ObjectIdentifier(sender)), "generation": String(generation),
                "control": control.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "anchor": anchor.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "coordinator": String(describing: ObjectIdentifier(self)),
                "window": sender.window.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "sourceAssociationValid": String(valid)
            ])
            #endif
            guard valid else { return }
            activate?(sender, generation)
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private enum TaskMenuFocusDiagnostics {
    private struct Event: Codable, Sendable {
        let sequence: Int
        let uptime: TimeInterval
        let wallTime: TimeInterval
        let stage: String
        let details: [String: String]
    }

    private struct Packet: Codable, Sendable {
        let session: String
        let replica: String
        let processID: Int32
        let dropped: Int
        let events: [Event]
    }

    private static var events: [Event] = []
    private static var dropped = 0
    private static var pending = false
    private static var written = 0
    private static var attempted = 0
    private static var attemptedDropped = 0
    private static var reportedExportError = false
    private static let output = DispatchQueue(label: "tsk.menu-focus-evidence", qos: .utility)

    static func record(_ stage: String, details: [String: String]) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let replica = environment["TSK_TEST_MENU_FOCUS_TRACE"], UUID(uuidString: replica) != nil,
              replica == environment["TSK_TEST_REPLICA_NAME"],
              let session = environment["TSK_UI_TEST_SESSION"], UUID(uuidString: session) != nil else { return }
        guard events.count < 256 else {
            dropped += 1
            export(session: session, replica: replica)
            return
        }
        events.append(Event(sequence: events.count + 1, uptime: ProcessInfo.processInfo.systemUptime,
                            wallTime: Date().timeIntervalSince1970, stage: stage, details: details))
        export(session: session, replica: replica)
    }

    private static func export(session: String, replica: String) {
        guard !pending, attempted != events.count || attemptedDropped != dropped else { return }
        pending = true
        DispatchQueue.main.async {
            let packet = Packet(session: session, replica: replica, processID: ProcessInfo.processInfo.processIdentifier,
                                dropped: dropped, events: events)
            attempted = packet.events.count
            attemptedDropped = packet.dropped
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                reportFailure("Documents directory unavailable", sequence: packet.events.count)
                pending = false
                return
            }
            let destination = directory.appendingPathComponent("participant-fixture-pr77-menu-focus-\(session)-\(packet.processID).json")
            output.async {
                let failure: String?
                do {
                    let data = try JSONEncoder().encode(packet)
                    try data.write(to: destination, options: .atomic)
                    failure = nil
                } catch { failure = String(describing: error) }
                DispatchQueue.main.async {
                    if let failure {
                        reportFailure(failure, sequence: packet.events.count)
                    } else { written = packet.events.count }
                    pending = false
                    export(session: session, replica: replica)
                }
            }
        }
    }

    private static func reportFailure(_ failure: String, sequence: Int) {
        guard !reportedExportError else { return }
        reportedExportError = true
        NSLog("[PR77-MENU-FOCUS] Export failed at %ld; last written %ld: %@", sequence, written, failure)
    }
}
#endif
