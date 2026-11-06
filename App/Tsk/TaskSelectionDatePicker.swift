import SwiftUI
import TskCore

struct TaskSelectionDatePicker: View {
    let store: TaskStore
    let field: TaskDateField
    @State private var change: TaskDateChange?
    @State private var choosingDate = false
    @State private var selectedDate: Date
    @State private var referenceDay: Date
    @State private var error: String?

    init(store: TaskStore, field: TaskDateField) {
        self.store = store
        self.field = field
        let day = Calendar.autoupdatingCurrent.startOfDay(for: store.currentDate)
        _selectedDate = State(initialValue: day)
        _referenceDay = State(initialValue: day)
    }

    private var parameter: TaskRowParameter { field == .scheduled ? .scheduled : .deadline }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(parameter.title, systemImage: parameter.symbol).font(.headline)
                    Text("Change \(store.selectedTaskIDs.count) selected tasks. Only \(parameter.title.lowercased()) changes when you apply.")
                        .font(.callout).foregroundStyle(.secondary)
                    choice("Today", id: "today", change: .day(referenceDay))
                    if let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: referenceDay) {
                        choice("Tomorrow", id: "tomorrow", change: .day(tomorrow))
                    }
                    Button {
                        choosingDate = true
                        change = .set(selectedDate)
                    } label: {
                        Label("Choose day", systemImage: choosingDate ? "checkmark.circle.fill" : "calendar")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("selection-choose-day")
                    if choosingDate {
                        TaskParameterDatePicker(parameter: parameter, selection: $selectedDate)
                            .onChange(of: selectedDate) { _, date in change = .set(date) }
                    }
                    choice(field == .scheduled ? "Remove scheduled day" : "Remove deadline", id: "remove", change: .remove)
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let change {
                    Text(summary(change)).font(.callout)
                        .accessibilityIdentifier("selection-date-pending")
                }
                if let error {
                    Text(error + " Review the selection or retry Apply.")
                        .font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("selection-date-error")
                }
                HStack {
                    Button("Cancel") { store.selectionDateField = nil }
                        .frame(minHeight: 44)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("cancel-selection-date")
                    Spacer()
                    Button("Apply") {
                        guard let change else { return }
                        Task {
                            if await store.changeSelectionDate(field: field, change: change) { store.selectionDateField = nil }
                            else { error = store.error }
                        }
                    }
                    .frame(minHeight: 44)
                    .keyboardShortcut(.defaultAction)
                    .disabled(change == nil)
                    .accessibilityIdentifier("apply-selection-date")
                }
            }
            .padding(16)
        }
        .frame(idealHeight: preferredHeight, maxHeight: preferredHeight)
        .buttonStyle(.borderless)
        .disabled(store.isSaving)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("selection-date-picker")
    }

    private var preferredHeight: CGFloat {
        if choosingDate { return 650 }
        if error != nil { return 600 }
        return change == nil ? 410 : 480
    }

    private func choice(_ title: String, id: String, change proposed: TaskDateChange) -> some View {
        Button {
            choosingDate = false
            change = proposed
        } label: {
            Label(title, systemImage: change == proposed ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityValue(change == proposed ? "Selected" : "Not selected")
        .accessibilityIdentifier("selection-date-" + id)
    }

    private func summary(_ change: TaskDateChange) -> String {
        switch change {
        case .remove: "Pending: remove \(parameter.title.lowercased())."
        case .day(let date): "Pending: \(date.formatted(date: .abbreviated, time: .omitted)). Existing times are kept."
        case .set(let date): "Pending: \(date.formatted(date: .abbreviated, time: .shortened))."
        }
    }
}
