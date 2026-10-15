import Foundation
import Dispatch

enum EventKitAccessPublication {
    enum Authorization { case notDetermined, fullAccess, denied, restricted, writeOnly, unavailable }
    enum Outcome: Equatable { case ready, insufficient, notReady }

    static func waitForFullAccess(
        isolation: isolated (any Actor)? = #isolation,
        authorization: () -> Authorization,
        now: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> Outcome {
        let started = now()
        while true {
            try Task.checkCancellation()
            switch authorization() {
            case .fullAccess:
                try Task.checkCancellation()
                return .ready
            case .notDetermined:
                let elapsed = now() &- started
                guard elapsed < 5_000_000_000 else { return .notReady }
                try await sleep(min(100_000_000, 5_000_000_000 - elapsed))
                try Task.checkCancellation()
                guard now() &- started < 5_000_000_000 else { return .notReady }
            case .denied, .restricted, .writeOnly, .unavailable: return .insufficient
            }
        }
    }
}

#if canImport(EventKit)
@preconcurrency import EventKit

@available(iOS 17.0, macOS 14.0, *)
extension EventKitAccessPublication.Authorization {
    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .fullAccess: self = .fullAccess
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .writeOnly: self = .writeOnly
        @unknown default: self = .unavailable
        }
    }
}
#endif
