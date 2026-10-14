import SwiftUI

@main
struct TskApp: App {
    @UIApplicationDelegateAdaptor(SynchronizationAppDelegate.self) private var synchronizationDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
