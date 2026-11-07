import SwiftUI
import TskCore

struct TaskSelectionDatePicker: View {
    let store: TaskStore
    let field: TaskDateField
    @State private var referenceDay: Date

    init(store: TaskStore, field: TaskDateField) {
        self.store = store
        self.field = field
        let day = Calendar.autoupdatingCurrent.startOfDay(for: store.currentDate)
        _referenceDay = State(initialValue: day)
    }

    private var parameter: TaskRowParameter { field == .scheduled ? .scheduled : .deadline }

    private var selectedDate: Binding<Date> {
        Binding(get: {
            let values = store.selectionTasks.map { $0.attributes[parameter.attribute] }
            let first = values.first ?? nil
            let common = values.allSatisfy { $0 == first } ? first : nil
            let original = field == .scheduled ? store.selectionTasks.first?.plannedDate : store.selectionTasks.first?.deadline
            if let change = store.selectionChanges[field], let date = try? change.resolvedDate(replacing: common) { return date }
            return common == nil ? referenceDay : original ?? referenceDay
        }, set: { date in
            store.error = nil
            store.selectionChanges[field] = .set(date)
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            Button { store.selectionDateField = nil } label: {
                HStack {
                    Label(parameter.title, systemImage: parameter.symbol)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Close " + parameter.title.lowercased() + " picker")
            .accessibilityIdentifier("close-selection-date")
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        choice("Today", id: "today", change: .day(referenceDay))
                        if let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: referenceDay) {
                            choice("Tomorrow", id: "tomorrow", change: .day(tomorrow))
                        }
                    }
                    TaskParameterDatePicker(parameter: parameter, selection: selectedDate)
                    HStack {
                        choice("Remove", id: "remove", change: .remove)
                        Spacer()
                        Button("Reset") { store.selectionChanges[field] = nil }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("reset-selection-date")
                    }
                    if let change = store.selectionChanges[field], store.selectionDateIsModified(field) {
                        Text(summary(change)).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("selection-date-pending")
                    }
                }
            }
            .frame(maxHeight: 400)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-date-picker")
    }

    private func choice(_ title: String, id: String, change: TaskDateChange) -> some View {
        let selected = store.selectionChanges[field] == change
        return Button {
            store.error = nil
            store.selectionChanges[field] = change
        } label: {
            Text(title).frame(minHeight: 44).padding(.horizontal, 12)
        }
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityLabel(id == "remove" ? "Remove " + parameter.title.lowercased() : title)
        .accessibilityIdentifier("selection-date-" + id)
    }

    private func summary(_ change: TaskDateChange) -> String {
        switch change {
        case .remove: "Remove \(parameter.title.lowercased()) when you tap Done."
        case .day(let date): "\(date.formatted(date: .abbreviated, time: .omitted)). Existing times are kept. Tap Done to save."
        case .set(let date): "\(date.formatted(date: .abbreviated, time: .shortened)). Tap Done to save."
        }
    }
}
