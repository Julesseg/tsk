import SwiftUI

extension Binding where Value == Date {
    func calendarDay(includesTime: Bool) -> Self {
        Binding(get: { wrappedValue }, set: { day in
            let calendar = Calendar.autoupdatingCurrent
            if includesTime {
                let time = calendar.dateComponents([.hour, .minute, .second], from: wrappedValue)
                if let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) {
                    wrappedValue = date
                }
            } else {
                wrappedValue = calendar.startOfDay(for: day)
            }
        })
    }
}
