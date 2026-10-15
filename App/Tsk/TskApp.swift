import SwiftUI
import AppIntents

@main
struct TskApp: App {
    @UIApplicationDelegateAdaptor(SynchronizationAppDelegate.self) private var synchronizationDelegate
    init() { TskShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if NativeKeyboardControlGate.enabled(ProcessInfo.processInfo.environment) {
                NativeKeyboardControlView()
            } else {
                TaskKeyboardHost { TaskStorageRootView() }.ignoresSafeArea()
            }
            #else
            TaskKeyboardHost { TaskStorageRootView() }.ignoresSafeArea()
            #endif
        }
    }
}
