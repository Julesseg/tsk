import Foundation
import TskNative

enum TaskUIBoundaryDiagnostics {
    static func event(_ stage: String, details: [String: String]) {
        #if DEBUG && targetEnvironment(simulator)
        guard let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: token) != nil else { return }
        TaskParticipantDiagnostics.event(stage, details: details)
        #endif
    }
}
