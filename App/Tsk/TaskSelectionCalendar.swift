import SwiftUI
import UIKit
import TskCore

@MainActor final class TaskSelectionCalendars: ObservableObject {
    private var available: [TaskDateField: UIDatePicker] = [:]
    private var prepared: Set<TaskDateField> = []

    func prepare(at date: Date) {
        for field in [TaskDateField.scheduled, .deadline] where !prepared.contains(field) {
            prepared.insert(field)
            let picker = makePicker(date: date)
            picker.bounds = CGRect(origin: .zero, size: picker.sizeThatFits(CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude)))
            picker.layoutIfNeeded()
            available[field] = picker
        }
    }

    func picker(for field: TaskDateField, date: Date) -> UIDatePicker {
        prepared.insert(field)
        let cached = available.removeValue(forKey: field)
        let picker = cached ?? makePicker(date: date)
        picker.removeFromSuperview()
        return picker
    }

    func release(_ picker: UIDatePicker, for field: TaskDateField) {
        picker.endEditing(true)
        if available[field] == nil { available[field] = picker }
    }

    private func makePicker(date: Date) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.date = date
        picker.accessibilityElementsHidden = true
        return picker
    }
}

struct TaskSelectionCalendar: UIViewRepresentable {
    let calendars: TaskSelectionCalendars
    let field: TaskDateField
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, calendars: calendars, field: field) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = calendars.picker(for: field, date: selection)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        picker.accessibilityIdentifier = field.rawValue + "-picker"
        picker.accessibilityLabel = field == .scheduled ? "Scheduled" : "Deadline"
        picker.accessibilityElementsHidden = false
        picker.isUserInteractionEnabled = true
        if picker.date != selection { picker.setDate(selection, animated: false) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let width = proposal.width ?? 340
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    static func dismantleUIView(_ picker: UIDatePicker, coordinator: Coordinator) {
        picker.removeTarget(coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        picker.accessibilityElementsHidden = true
        picker.isUserInteractionEnabled = false
        coordinator.calendars.release(picker, for: coordinator.field)
    }

    final class Coordinator {
        var selection: Binding<Date>
        let calendars: TaskSelectionCalendars
        let field: TaskDateField

        init(selection: Binding<Date>, calendars: TaskSelectionCalendars, field: TaskDateField) {
            self.selection = selection
            self.calendars = calendars
            self.field = field
        }

        @objc func changed(_ picker: UIDatePicker) { selection.wrappedValue = picker.date }
    }
}
