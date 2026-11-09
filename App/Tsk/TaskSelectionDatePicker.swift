import SwiftUI
import TskCore

struct TaskSelectionDatePicker: View {
    let store: TaskStore
    let field: TaskDateField
    @State private var referenceDay: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(spacing: 4) {
            HStack {
                Label(parameter.title, systemImage: parameter.symbol)
                Spacer()
                Button { store.selectionDateField = nil } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close " + parameter.title.lowercased() + " picker")
                .accessibilityIdentifier("close-selection-date")
            }
            HStack(spacing: 6) {
                choice("Today", id: "today", change: .day(referenceDay))
                if let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: referenceDay) {
                    choice("Tomorrow", id: "tomorrow", change: .day(tomorrow))
                }
                Button { store.selectionChanges[field] = nil } label: {
                    actionLabel("Reset", color: .orange)
                }
                .accessibilityIdentifier("reset-selection-date")
                choice("Remove", id: "remove", change: .remove, color: .red)
            }
            .font(.caption.weight(.semibold))
            TaskParameterDatePicker(parameter: parameter, selection: selectedDate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-date-picker")
        .accessibilityValue(store.selectionChanges[field].map(summary) ?? "Unchanged")
    }

    private func actionLabel(_ title: String, color: Color = .primary, tint: Color = .accentColor, selected: Bool = false) -> some View {
        Text(title)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 32)
            .glassEffect(.regular.tint(selected ? tint.opacity(0.2) : .clear).interactive(), in: Capsule())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }

    private func choice(_ title: String, id: String, change: TaskDateChange, color: Color = .primary) -> some View {
        let selected = store.selectionChanges[field] == change
        return Button {
            store.error = nil
            store.selectionChanges[field] = change
        } label: {
            actionLabel(title, color: color, tint: change == .remove ? .red : .accentColor, selected: selected)
        }
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
