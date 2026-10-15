import SwiftUI
import AppIntents

@main
struct TskApp: App {
    @UIApplicationDelegateAdaptor(SynchronizationAppDelegate.self) private var synchronizationDelegate
    init() { TskShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            TaskKeyboardHost { TaskStorageRootView() }.ignoresSafeArea()
        }
    }
}
