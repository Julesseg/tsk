import Foundation
import TskCore

@available(iOS 16, macOS 13, *)
@MainActor public final class ForegroundTaskNavigation {
    public static let shared = ForegroundTaskNavigation()
    private var handler: (@MainActor (TaskActionURL) async throws -> Void)?

    public init() {}

    public func connect(_ handler: @escaping @MainActor (TaskActionURL) async throws -> Void) {
        self.handler = handler
    }

    public func open(_ action: TaskActionURL) async throws {
        guard case .add = action else {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while handler == nil {
                guard ContinuousClock.now < deadline else {
                    throw TaskActionError.navigationFailed("The task workspace is not ready. Open tsk and try again.")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            try await handler?(action)
            return
        }
        throw TaskActionError.invalidInput("Background data actions do not use foreground navigation.")
    }
}
