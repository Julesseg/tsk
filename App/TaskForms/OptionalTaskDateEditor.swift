import SwiftUI

struct OptionalTaskDateEditor: View {
    let title: String
    let identifier: String
    let rawValue: String?
    @Binding var date: Date?
    let initialDate: Date

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { rawValue != nil },
            set: { date = $0 ? initialDate : nil }
        ))
        .accessibilityIdentifier("\(identifier)-enabled")
        if rawValue != nil {
            if let date {
                DatePicker(title, selection: Binding(
                    get: { date }, set: { self.date = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("\(identifier)-picker")
            } else {
                Text("Unrecognized \(title.lowercased()): \(rawValue ?? "")").font(.caption)
                Button("Replace \(title.lowercased())") { date = initialDate }
                    .accessibilityIdentifier("replace-\(identifier)")
            }
        }
    }
}
