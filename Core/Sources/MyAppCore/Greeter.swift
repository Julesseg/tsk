import Foundation

// Placeholder domain logic. Replace with your app's core model — everything
// that doesn't need UIKit/SwiftUI belongs in this package so it stays
// testable with `swift test` on Linux CI.
public enum Greeter {
    public static func greeting(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hello, world!" : "Hello, \(trimmed)!"
    }
}
