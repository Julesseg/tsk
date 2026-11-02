#if DEBUG && targetEnvironment(simulator)
import Foundation
import ObjectiveC
import UIKit

private struct NativeTouchRecord: Codable, Sendable {
    let sequence: Int
    let stage: String
    let uptime: TimeInterval
    let wallTime: TimeInterval
    let details: [String: String]
    let ancestors: [[String: String]]
    let recognizers: [[String: String]]
}

private struct NativeTouchExport: Codable, Sendable {
    let schema: Int
    let session: String
    let replica: String
    let processID: Int32
    let evictedRecords: Int
    let records: [NativeTouchRecord]
}

@MainActor
enum TaskNativeTouchDiagnostics {
    private static var installed = false
    private static var session = ""
    private static var replica = ""
    private static var records: [NativeTouchRecord] = []
    private static var sequence = 0
    private static var evictedRecords = 0
    private static var exportPending = false
    private static var lastExportedSequence = 0
    private static var expandedOwner: String?
    private static var keyboardApplyOrdinals: [String: Int] = [:]
    private static var mainRebuildRequestOrdinals: [String: Int] = [:]
    private static var destination: URL?
    private static let output = DispatchQueue(label: "tsk.pr77.native-touch-export", qos: .utility)

    static var isRecording: Bool { installed }

    static func installIfRequested(application: UIApplication) {
        let environment = ProcessInfo.processInfo.environment
        guard !installed,
              environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let requested = environment["TSK_TEST_NATIVE_TOUCH_TRACE"],
              requested == environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: requested) != nil,
              let token = environment["TSK_UI_TEST_SESSION"], UUID(uuidString: token) != nil,
              let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let observer = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.tsk_pr77_sendEvent(_:))),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        session = token
        replica = requested
        destination = directory.appendingPathComponent("participant-fixture-pr77-touch-\(token)-\(ProcessInfo.processInfo.processIdentifier).json")
        method_exchangeImplementations(original, observer)
        installed = true
        append("installed", details: ["applicationClass": NSStringFromClass(type(of: application))])
        exportAfterDispatch()
    }

    static func parameterChanged(_ editing: TaskRowEditing, previous: TaskRowParameter?, current: TaskRowParameter?) {
        guard installed else { return }
        append("parameter.write", details: [
            "owner": identity(editing), "expandedOwner": expandedOwner ?? "nil", "rowID": editing.rowID,
            "previous": previous?.rawValue ?? "nil", "current": current?.rawValue ?? "nil"
        ])
        exportAfterDispatch()
    }

    static func expansionChanged(_ editing: TaskRowEditing, expanded: Bool) {
        guard installed else { return }
        let owner = identity(editing)
        if expanded { expandedOwner = owner }
        else if expandedOwner == owner { expandedOwner = nil }
        append("row.expanded", details: ["owner": owner, "rowID": editing.rowID, "expanded": String(expanded)])
        exportAfterDispatch()
    }

    static func keyboardRegistrationWillApply(router: UUID, ordinal: Int, details: [String: String]) {
        guard installed else { return }
        keyboardApplyOrdinals[router.uuidString] = max(keyboardApplyOrdinals[router.uuidString] ?? 0, ordinal)
        append("keyboard-registration.apply", details: details.merging([
            "router": router.uuidString, "applyOrdinal": String(ordinal)
        ]) { _, current in current })
        exportAfterDispatch()
    }

    static func mainRebuildRequest(router: UUID, applyOrdinal: Int, requestOrdinal: Int, phase: String) {
        guard installed else { return }
        mainRebuildRequestOrdinals[router.uuidString] = max(mainRebuildRequestOrdinals[router.uuidString] ?? 0, requestOrdinal)
        append("main-rebuild.request." + phase, details: [
            "router": router.uuidString, "applyOrdinal": String(applyOrdinal),
            "requestOrdinal": String(requestOrdinal), "menuSystem": "main"
        ])
        exportAfterDispatch()
    }

    static func receive(_ event: UIEvent, stage: String) {
        guard installed, event.type == .touches else { return }
        for touch in (event.allTouches ?? []).prefix(4) {
            guard touch.phase != .stationary else { continue }
            let location = touch.location(in: touch.window)
            var ancestors: [[String: String]] = []
            var view = touch.view
            while let current = view, ancestors.count < 16 {
                ancestors.append([
                    "id": identity(current), "class": NSStringFromClass(type(of: current)),
                    "identifier": String((current.accessibilityIdentifier ?? "").prefix(160)),
                    "frame": NSCoder.string(for: current.frame), "bounds": NSCoder.string(for: current.bounds),
                    "windowFrame": NSCoder.string(for: current.convert(current.bounds, to: current.window)),
                    "window": current.window.map(identity) ?? "nil", "superview": current.superview.map(identity) ?? "nil",
                    "hidden": String(current.isHidden), "alpha": String(describing: current.alpha),
                    "interactionEnabled": String(current.isUserInteractionEnabled)
                ])
                view = current.superview
            }
            let recognizers = (touch.gestureRecognizers ?? []).prefix(16).map { recognizer in
                [
                    "id": identity(recognizer), "class": NSStringFromClass(type(of: recognizer)),
                    "view": recognizer.view.map(identity) ?? "nil", "state": String(recognizer.state.rawValue),
                    "enabled": String(recognizer.isEnabled), "cancelsTouches": String(recognizer.cancelsTouchesInView),
                    "delaysBegan": String(recognizer.delaysTouchesBegan), "delaysEnded": String(recognizer.delaysTouchesEnded)
                ]
            }
            append(stage, details: [
                "event": identity(event), "eventTimestamp": String(event.timestamp),
                "touch": identity(touch), "touchTimestamp": String(touch.timestamp),
                "phase": String(touch.phase.rawValue), "type": String(touch.type.rawValue),
                "tapCount": String(touch.tapCount), "location": NSCoder.string(for: location),
                "view": touch.view.map(identity) ?? "nil", "window": touch.window.map(identity) ?? "nil",
                "keyboardApplyOrdinals": ordinalSignature(keyboardApplyOrdinals),
                "mainRebuildRequestOrdinals": ordinalSignature(mainRebuildRequestOrdinals),
                "ancestorLimitReached": String(view != nil),
                "recognizersTruncated": String((touch.gestureRecognizers?.count ?? 0) > 16)
            ], ancestors: ancestors, recognizers: recognizers)
        }
    }

    static func exportAfterDispatch() {
        guard installed, !exportPending, sequence != lastExportedSequence else { return }
        exportPending = true
        DispatchQueue.main.async {
            guard let destination else { return }
            let exportedSequence = sequence
            let packet = NativeTouchExport(schema: 1, session: session, replica: replica,
                                           processID: ProcessInfo.processInfo.processIdentifier,
                                           evictedRecords: evictedRecords, records: records)
            output.async {
                do {
                    let data = try JSONEncoder().encode(packet)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    NSLog("[PR77-TOUCH] Export failed: %@", String(describing: error))
                }
                DispatchQueue.main.async {
                    lastExportedSequence = exportedSequence
                    exportPending = false
                    exportAfterDispatch()
                }
            }
        }
    }

    private static func append(_ stage: String, details: [String: String], ancestors: [[String: String]] = [], recognizers: [[String: String]] = []) {
        sequence += 1
        if records.count == 512 {
            records.removeFirst()
            evictedRecords += 1
        }
        records.append(NativeTouchRecord(sequence: sequence, stage: stage,
                                         uptime: ProcessInfo.processInfo.systemUptime, wallTime: Date().timeIntervalSince1970,
                                         details: details, ancestors: ancestors, recognizers: recognizers))
    }

    private static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    private static func ordinalSignature(_ values: [String: Int]) -> String {
        values.sorted { $0.key < $1.key }.map { $0.key + ":" + String($0.value) }.joined(separator: ",")
    }
}

extension UIApplication {
    @objc dynamic func tsk_pr77_sendEvent(_ event: UIEvent) {
        TaskNativeTouchDiagnostics.receive(event, stage: "touch.before")
        tsk_pr77_sendEvent(event)
        TaskNativeTouchDiagnostics.receive(event, stage: "touch.after")
        TaskNativeTouchDiagnostics.exportAfterDispatch()
    }
}
#endif
