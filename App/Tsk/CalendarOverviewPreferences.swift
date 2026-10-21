import Foundation
import Observation
import TskCore

@MainActor @Observable final class CalendarOverviewPreferences {
    static let shared = CalendarOverviewPreferences()
    private let defaults: UserDefaults
    var hours: CalendarDisplayHours {
        didSet { defaults.set(try? JSONEncoder().encode(hours), forKey: "calendar-overview-hours") }
    }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? Self.applicationDefaults()
        self.defaults = defaults
        hours = defaults.data(forKey: "calendar-overview-hours").flatMap { try? JSONDecoder().decode(CalendarDisplayHours.self, from: $0) } ?? CalendarDisplayHours()
    }

    private static func applicationDefaults() -> UserDefaults {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let replica = environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: replica) != nil,
           let defaults = UserDefaults(suiteName: "tsk.calendar-ui.\(replica)") { return defaults }
        #endif
        return .standard
    }
}
