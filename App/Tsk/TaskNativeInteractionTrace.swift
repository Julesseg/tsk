import SwiftUI
import UIKit

@MainActor enum TaskNativeInteractionTrace {
    static let enabled: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        return environment["TSK_DEBUG_PR77_NATIVE_TRACE"] == "1"
            && UUID(uuidString: environment["TSK_UI_TEST_SESSION"] ?? "") != nil
        #else
        return false
        #endif
    }()
    private static let observer = NativeTraceObserver()
    private static var records: [[String: Any]] = []
    private static var controls: [ObjectIdentifier: WeakTraceObject<UIControl>] = [:]
    private static var recognizers: [ObjectIdentifier: WeakTraceObject<UIGestureRecognizer>] = [:]
    private static var scopes: [ObjectIdentifier: WeakTraceObject<UIView>] = [:]
    private static var scopeWindows: [ObjectIdentifier: WeakTraceObject<UIWindow>] = [:]
    private static var coverage: [String: [String: Any]] = [:]
    private static var pendingWindows = Set<ObjectIdentifier>()
    private static var sampledChanges = Set<ObjectIdentifier>()
    private static var panels: [String: UUID] = [:]
    private static var flushPending = false
    private static var dropped = 0
    private static var scrollSamples = 0
    private static var reportedWriteFailure = false

    static func event(_ name: String, _ fields: [String: Any] = [:], flush: Bool = true) {
        guard enabled else { return }
        if records.count == 384 { records.removeFirst(); dropped += 1 }
        records.append(["event": name, "time": ProcessInfo.processInfo.systemUptime,
                        "pid": ProcessInfo.processInfo.processIdentifier, "panels": panels.mapValues(\.uuidString), "fields": fields])
        if flush { scheduleFlush() }
    }

    static func panel(_ scope: String?, id: UUID, active: Bool) {
        guard enabled, let scope else { return }
        if active { panels[scope] = id }
        event(active ? "panel.appeared" : "panel.disappeared", ["scope": scope, "panel": id.uuidString])
        if !active { panels.removeValue(forKey: scope) }
        refreshOwnedWindows("panel." + scope)
    }

    static func refreshOwnedWindows(_ reason: String) {
        guard enabled else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden { refresh(window, reason: reason) }
        }
    }

    static func refresh(_ window: UIWindow, reason: String, scope: UIView? = nil) {
        guard enabled else { return }
        if let scope {
            scopes[ObjectIdentifier(scope)] = WeakTraceObject(scope)
            scopeWindows[ObjectIdentifier(scope)] = WeakTraceObject(window)
        }
        let windowID = ObjectIdentifier(window)
        guard pendingWindows.insert(windowID).inserted else { return }
        DispatchQueue.main.async { [weak window] in
            pendingWindows.remove(windowID)
            guard let window else { return }
            register(window, reason: reason)
        }
    }

    static func removeScope(_ scope: UIView) {
        guard enabled else { return }
        let key = ObjectIdentifier(scope)
        scopes.removeValue(forKey: key)
        if let window = scopeWindows.removeValue(forKey: key)?.value {
            refresh(window, reason: "scope.removed")
        }
    }

    private static func register(_ window: UIWindow, reason: String) {
        controls = controls.filter { $0.value.value != nil }
        recognizers = recognizers.filter { $0.value.value != nil }
        scopes = scopes.filter { $0.value.value != nil }
        scopeWindows = scopeWindows.filter { scopes[$0.key] != nil }
        var roots = Set<ObjectIdentifier>()
        var ancestors = Set<ObjectIdentifier>()
        for scope in scopes.values.compactMap(\.value) where scope.window === window {
            var current: UIView? = scope
            while let view = current {
                if view is UICollectionViewCell || view is UITableViewCell {
                    roots.insert(ObjectIdentifier(view))
                    current = view.superview
                    while let ancestor = current {
                        ancestors.insert(ObjectIdentifier(ancestor))
                        current = ancestor.superview
                    }
                    break
                }
                current = view.superview
            }
        }
        var pending: [(UIView, Bool)] = [(window, false)]
        var visited = 0
        var addedControls: [[String: Any]] = []
        var addedRecognizers: [[String: Any]] = []
        var scopedRecognizers = Set<ObjectIdentifier>()
        var liveControls: [[String: Any]] = []
        while visited < 2048, let (view, inheritedScope) = pending.popLast() {
            visited += 1
            guard !view.isHidden else { continue }
            let inScope = inheritedScope || roots.contains(ObjectIdentifier(view))
            if let control = view as? UIControl,
               control is UISwitch || (control as? UIButton)?.showsMenuAsPrimaryAction == true {
                liveControls.append(viewRecord(control))
            }
            if let control = view as? UIControl,
               control is UISwitch || (control as? UIButton)?.showsMenuAsPrimaryAction == true,
               controls[ObjectIdentifier(control)]?.value !== control {
                controls[ObjectIdentifier(control)] = WeakTraceObject(control)
                if control is UISwitch {
                    control.addTarget(observer, action: #selector(NativeTraceObserver.down(_:event:)), for: .touchDown)
                    control.addTarget(observer, action: #selector(NativeTraceObserver.up(_:event:)), for: .touchUpInside)
                    control.addTarget(observer, action: #selector(NativeTraceObserver.cancel(_:event:)), for: .touchCancel)
                    control.addTarget(observer, action: #selector(NativeTraceObserver.changed(_:event:)), for: .valueChanged)
                } else {
                    control.addTarget(observer, action: #selector(NativeTraceObserver.menu(_:event:)), for: .menuActionTriggered)
                }
                addedControls.append(viewRecord(control))
            }
            for recognizer in view.gestureRecognizers ?? [] where inScope || ancestors.contains(ObjectIdentifier(view)) {
                scopedRecognizers.insert(ObjectIdentifier(recognizer))
                guard recognizers[ObjectIdentifier(recognizer)]?.value !== recognizer else { continue }
                recognizers[ObjectIdentifier(recognizer)] = WeakTraceObject(recognizer)
                recognizer.addTarget(observer, action: #selector(NativeTraceObserver.gesture(_:)))
                addedRecognizers.append(recognizerRecord(recognizer))
            }
            pending.append(contentsOf: view.subviews.reversed().map { ($0, inScope) })
        }
        if pending.isEmpty {
            for (key, weakRecognizer) in recognizers where !scopedRecognizers.contains(key) {
                guard let recognizer = weakRecognizer.value, recognizer.view?.window === window else { continue }
                recognizer.removeTarget(observer, action: #selector(NativeTraceObserver.gesture(_:)))
                recognizers.removeValue(forKey: key)
                sampledChanges.remove(key)
            }
        }
        coverage = coverage.filter { $0.key == identity(window) || ($0.value["time"] as? Double ?? 0) > ProcessInfo.processInfo.systemUptime - 120 }
        coverage[identity(window)] = ["time": ProcessInfo.processInfo.systemUptime, "reason": reason,
                                      "visited": visited, "truncated": !pending.isEmpty,
                                      "rowRootCount": roots.count, "controls": liveControls,
                                      "recognizerCount": recognizers.values.compactMap(\.value).filter { $0.view?.window === window }.count]
        if !addedControls.isEmpty || !addedRecognizers.isEmpty || !pending.isEmpty {
            event("registration", ["reason": reason, "window": identity(window), "visited": visited,
                                   "truncated": !pending.isEmpty, "controls": Array(addedControls.prefix(24)),
                                   "recognizers": Array(addedRecognizers.prefix(48)),
                                   "controlMetadataTruncated": addedControls.count > 24,
                                   "recognizerMetadataTruncated": addedRecognizers.count > 48,
                                   "controlCount": addedControls.count, "recognizerCount": addedRecognizers.count])
        }
        if reason != "keyboard-scope" { scheduleFlush() }
    }

    fileprivate static func control(_ sender: UIControl, event input: UIEvent?, kind: String) {
        guard enabled else { return }
        var fields: [String: Any] = ["control": viewRecord(sender)]
        if let toggle = sender as? UISwitch { fields["isOn"] = toggle.isOn }
        if let touch = input?.allTouches?.first, let window = sender.window {
            let point = touch.location(in: window)
            fields["touchView"] = touch.view.map(viewRecord) ?? [:]
            fields["touchPoint"] = [point.x, point.y]
            fields["touchPhase"] = touch.phase.rawValue
            fields["freshHitTest"] = window.hitTest(point, with: input).map(viewRecord) ?? [:]
        }
        event("control." + kind, fields)
        if kind == "menu" { refreshOwnedWindows("menu.triggered") }
    }

    fileprivate static func gesture(_ recognizer: UIGestureRecognizer) {
        guard enabled else { return }
        let key = ObjectIdentifier(recognizer)
        switch recognizer.state {
        case .began: sampledChanges.remove(key)
        case .changed: guard sampledChanges.insert(key).inserted else { return }
        case .ended, .cancelled: sampledChanges.remove(key)
        default: return
        }
        var fields = recognizerRecord(recognizer)
        if let window = recognizer.view?.window {
            let point = recognizer.location(in: window)
            let hit = window.hitTest(point, with: nil)
            fields["location"] = [point.x, point.y]
            fields["freshHitTest"] = hit.map(viewRecord) ?? [:]
            var ancestors: [[String: Any]] = []
            var current = hit
            while let view = current, ancestors.count < 12 {
                ancestors.append(viewRecord(view))
                current = view.superview
            }
            fields["hitAncestors"] = ancestors
            let peers = recognizers.values.compactMap(\.value).filter { $0.view?.window === window }
            fields["activePeers"] = peers.filter { $0.state == .began || $0.state == .changed }.prefix(12).map(recognizerRecord)
        }
        event("gesture", fields, flush: recognizer.state == .ended || recognizer.state == .cancelled)
    }

    static func scroll(_ values: [CGFloat]) {
        guard enabled else { return }
        scrollSamples += 1
        event("row.scrollGeometry", ["contentWidth": values[0], "containerWidth": values[1],
                                     "offsetX": values[2], "boundsWidth": values[3]], flush: false)
    }

    private static func identity(_ value: AnyObject?) -> String {
        value.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    }

    private static func rect(_ value: CGRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }

    private static func viewRecord(_ view: UIView) -> [String: Any] {
        var fields: [String: Any] = ["id": identity(view), "type": String(describing: type(of: view)),
                                   "identifier": view.accessibilityIdentifier ?? "", "frame": rect(view.convert(view.bounds, to: view.window)),
                                   "window": identity(view.window), "interaction": view.isUserInteractionEnabled]
        if let scroll = view as? UIScrollView {
            fields["contentSize"] = [scroll.contentSize.width, scroll.contentSize.height]
            fields["bounds"] = rect(scroll.bounds)
            fields["offset"] = [scroll.contentOffset.x, scroll.contentOffset.y]
            fields["enabled"] = scroll.isScrollEnabled
            fields["insets"] = [scroll.adjustedContentInset.top, scroll.adjustedContentInset.left,
                                scroll.adjustedContentInset.bottom, scroll.adjustedContentInset.right]
        }
        return fields
    }

    private static func recognizerRecord(_ recognizer: UIGestureRecognizer) -> [String: Any] {
        var fields: [String: Any] = ["id": identity(recognizer), "type": String(describing: type(of: recognizer)),
                                   "state": recognizer.state.rawValue, "enabled": recognizer.isEnabled,
                                   "view": recognizer.view.map(viewRecord) ?? [:]]
        if let pan = recognizer as? UIPanGestureRecognizer {
            let translation = pan.translation(in: pan.view)
            let velocity = pan.velocity(in: pan.view)
            fields["translation"] = [translation.x, translation.y]
            fields["velocity"] = [velocity.x, velocity.y]
        }
        return fields
    }

    private static func scheduleFlush() {
        guard !flushPending else { return }
        flushPending = true
        DispatchQueue.main.async {
            flushPending = false
            let environment = ProcessInfo.processInfo.environment
            let session = environment["TSK_UI_TEST_SESSION"] ?? "missing"
            let pid = ProcessInfo.processInfo.processIdentifier
            let receipt: [String: Any] = ["records": records, "dropped": dropped, "scrollSamples": scrollSamples, "coverage": coverage,
                                        "session": session, "replica": environment["TSK_TEST_REPLICA_NAME"] ?? "missing"]
            do {
                let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                try data.write(to: directory.appendingPathComponent("participant-fixture-pr77-native-\(session)-\(pid).json"), options: .atomic)
            } catch {
                if !reportedWriteFailure {
                    reportedWriteFailure = true
                    print("[PR77-native-trace] Receipt write failed: \(error)")
                }
            }
        }
    }
}

struct TaskNativeScrollTrace: ViewModifier {
    func body(content: Content) -> some View {
        if TaskNativeInteractionTrace.enabled {
            content.onScrollGeometryChange(for: [CGFloat].self) { geometry in
                [geometry.contentSize.width, geometry.containerSize.width, geometry.contentOffset.x, geometry.bounds.width]
            } action: { _, values in
                TaskNativeInteractionTrace.scroll(values)
            }
        } else {
            content
        }
    }
}

private final class WeakTraceObject<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

@MainActor private final class NativeTraceObserver: NSObject {
    @objc func down(_ sender: UIControl, event: UIEvent?) { TaskNativeInteractionTrace.control(sender, event: event, kind: "down") }
    @objc func up(_ sender: UIControl, event: UIEvent?) { TaskNativeInteractionTrace.control(sender, event: event, kind: "up") }
    @objc func cancel(_ sender: UIControl, event: UIEvent?) { TaskNativeInteractionTrace.control(sender, event: event, kind: "cancel") }
    @objc func changed(_ sender: UIControl, event: UIEvent?) { TaskNativeInteractionTrace.control(sender, event: event, kind: "valueChanged") }
    @objc func menu(_ sender: UIControl, event: UIEvent?) { TaskNativeInteractionTrace.control(sender, event: event, kind: "menu") }
    @objc func gesture(_ recognizer: UIGestureRecognizer) { TaskNativeInteractionTrace.gesture(recognizer) }
}
