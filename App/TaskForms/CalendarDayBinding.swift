import SwiftUI

extension Binding where Value == Date {
    func calendarDay(includesTime: Bool) -> Self {
        Binding(get: { wrappedValue }, set: { day in
            let calendar = Calendar.autoupdatingCurrent
            if includesTime {
                if let date = calendar.date(on: day, keepingTimeFrom: wrappedValue) {
                    wrappedValue = date
                }
            } else {
                wrappedValue = calendar.startOfDay(for: day)
            }
        })
    }
}

extension Calendar {
    func date(on day: Date, keepingTimeFrom date: Date) -> Date? {
        let time = dateComponents([.hour, .minute, .second], from: date)
        return self.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
    }
}
