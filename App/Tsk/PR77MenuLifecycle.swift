import UIKit

@MainActor enum PR77MenuLifecycle {
    static let enabled: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        return environment["TSK_DEBUG_PR77_MENU_LIFECYCLE"] == "1" && UUID(uuidString: environment["TSK_UI_TEST_SESSION"] ?? "") != nil
        #else
        return false
        #endif
    }()
    static var events: [[String: Any]] = []
    static var observers: [NSObjectProtocol] = []

    static func install() {
        guard enabled, observers.isEmpty else { return }
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification,
                     UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let eventName = "keyboard." + note.name.rawValue
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                MainActor.assumeIsolated {
                    var details: [String: Any] = [:]
                    if let frame { details["keyboardFrame"] = rect(frame) }
                    record(eventName, details: details)
                }
            })
        }
    }

    static func rect(_ value: CGRect) -> [Double] {
        [value.minX, value.minY, value.width, value.height].map(Double.init)
    }

    static func firstResponder(_ view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for child in view.subviews { if let found = firstResponder(child) { return found } }
        return nil
    }

    static func controllerResponder(_ controller: UIViewController) -> UIResponder? {
        if controller.isFirstResponder { return controller }
        for child in controller.children { if let found = controllerResponder(child) { return found } }
        if let presented = controller.presentedViewController { return controllerResponder(presented) }
        return nil
    }

    static func identity(_ value: AnyObject?) -> String { value.map { String(describing: ObjectIdentifier($0)) } ?? "nil" }

    static func record(_ name: String, button: TaskRowMenuControl? = nil, details: [String: Any] = [:], persist: Bool = false) {
        guard enabled, events.count < 256 else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var entry: [String: Any] = ["event": name, "time": ProcessInfo.processInfo.systemUptime,
                                   "pid": ProcessInfo.processInfo.processIdentifier, "mainThread": Thread.isMainThread,
                                   "animationsEnabled": UIView.areAnimationsEnabled, "inheritedAnimationDuration": UIView.inheritedAnimationDuration, "details": details]
        entry["windows"] = windows.map { window -> [String: Any] in
            let responder = firstResponder(window) ?? window.rootViewController.flatMap { controllerResponder($0) }
            return ["id": identity(window), "type": String(describing: type(of: window)), "frame": rect(window.frame),
                    "key": window.isKeyWindow, "hidden": window.isHidden,
                    "responder": responder.map { String(describing: type(of: $0)) } ?? "nil",
                    "responderID": identity(responder), "textInput": responder is any UITextInput, "keyInput": responder is any UIKeyInput]
        }
        if let button {
            entry["button"] = ["id": identity(button), "identifier": button.accessibilityIdentifier ?? "nil",
                               "window": identity(button.window), "superview": identity(button.superview),
                               "frame": rect(button.frame), "bounds": rect(button.bounds), "labelFrame": rect(button.label.frame),
                               "menu": identity(button.menu), "firstResponder": button.isFirstResponder,
                               "highlighted": button.isHighlighted, "intrinsicCalls": button.pr77IntrinsicCalls,
                               "layoutCalls": button.pr77LayoutCalls, "frameChanges": button.pr77FrameChanges,
                               "sizeChanges": button.pr77SizeChanges, "updateCalls": button.pr77UpdateCalls,
                               "menuAssignments": button.pr77MenuAssignments, "labelAssignments": button.pr77LabelAssignments]
        }
        events.append(entry)
        if persist, let library = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: library.appendingPathComponent("participant-fixture-pr77-menu-lifecycle.json"), options: .atomic)
        }
    }
}
