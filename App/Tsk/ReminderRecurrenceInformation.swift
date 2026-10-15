import SwiftUI
import TskCore

struct ReminderRecurrenceInformation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ReminderRecurrenceMapping.supportedDescription)
            Text("Converted reminders become recurring templates anchored at their current incomplete occurrence. A single designated Taskwarrior client creates future occurrences after sync and a recurrence-enabled report; sync alone does not generate tasks.")
            Text("An older incomplete anchor can cause the external generator to create missed occurrences.")
        }
        .font(.footnote)
        .accessibilityIdentifier("reminders-recurrence-support")
    }
}
