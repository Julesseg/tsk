import SwiftUI
import TskCore

struct ReminderListMappingSection: View {
    let lists: [ReminderList]
    @Binding var projects: [String: String]
    let focused: FocusState<Bool>.Binding
    var changed: () -> Void = {}

    var body: some View {
        Section("Lists and destination projects") {
            if lists.isEmpty { Text("No lists loaded. Allow access and refresh. If no source is available, configure a Reminders account in Settings.") }
            ForEach(lists) { list in
                Toggle(list.title, isOn: Binding(get: { projects[list.id] != nil }, set: { selected in
                    projects[list.id] = selected ? list.title : nil; changed()
                })).accessibilityIdentifier("reminders-list-\(list.title)")
                if projects[list.id] != nil {
                    TextField("Destination project for \(list.title)", text: Binding(get: { projects[list.id] ?? "" }, set: { projects[list.id] = $0; changed() }))
                        .focused(focused).autocorrectionDisabled()
                        .accessibilityIdentifier("reminders-project-\(list.title)")
                }
            }
        }
    }
}
