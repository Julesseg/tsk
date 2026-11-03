import SwiftUI
import AppIntents
import UIKit

@main
struct TskApp: App {
    @UIApplicationDelegateAdaptor(SynchronizationAppDelegate.self) private var synchronizationDelegate
    init() {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["TSK_UI_DISABLE_ANIMATIONS"] == "1",
           let session = environment["TSK_UI_TEST_SESSION"], UUID(uuidString: session) != nil {
            UIView.setAnimationsEnabled(false)
        }
        #endif
        TskShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let mode = NativeMenuFocusControlGate.mode(ProcessInfo.processInfo.environment) {
                if mode == .hosted || mode == .firstClaimOmitted {
                    TaskKeyboardHost { NativeMenuFocusControlView() }
                } else if mode == .defaultBehavior {
                    NativeMenuDefaultKeyboardHost { NativeMenuFocusControlView() }
                } else {
                    NativeMenuFocusControlView()
                }
            } else if NativeKeyboardControlGate.enabled(ProcessInfo.processInfo.environment) {
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
