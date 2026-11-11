import Foundation
import Observation
import TskCore

@MainActor @Observable final class CalendarOverviewPreferences {
    static let shared = CalendarOverviewPreferences()
    private let defaults: UserDefaults
    var hours: CalendarDisplayHours {
        didSet { defaults.set(try? JSONEncoder().encode(hours), forKey: "calendar-overview-hours") }
    }
    var visibility: CalendarVisibility {
        didSet { defaults.set(try? JSONEncoder().encode(visibility), forKey: "calendar-visibility") }
    }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? Self.applicationDefaults()
        self.defaults = defaults
        visibility = defaults.data(forKey: "calendar-visibility").flatMap { try? JSONDecoder().decode(CalendarVisibility.self, from: $0) } ?? CalendarVisibility()
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
