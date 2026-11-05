import Foundation

@MainActor final class TaskRowMotion {
    init(duration: TimeInterval, update: @escaping (Double) -> Void) {}
    func cancel() {}
    func run() async {}
}

enum TaskParticipantDiagnostics {
    static func begin(_ name: String) -> Int { 0 }
    static func end(_ name: String, id: Int) {}
}
