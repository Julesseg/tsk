import SwiftUI
import UIKit
import TskCore

@MainActor final class TaskSelectionCalendars {
    private var available: UIDatePicker?

    func picker(date: Date) -> UIDatePicker {
        guard let picker = available else { return makePicker(date: date) }
        available = nil
        picker.removeFromSuperview()
        return picker
    }

    func release(_ picker: UIDatePicker) {
        picker.endEditing(true)
        if available == nil { available = picker }
    }

    private func makePicker(date: Date) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
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
    let minimumDate: Date?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, calendars: calendars) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = calendars.picker(date: selection)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.minimumDate != minimumDate { picker.minimumDate = minimumDate }
        picker.accessibilityIdentifier = field.rawValue + "-picker"
        picker.accessibilityLabel = field == .scheduled ? "Scheduled" : "Deadline"
        picker.accessibilityElementsHidden = false
        picker.isUserInteractionEnabled = true
        let date = selection
        if picker.date != date { picker.setDate(date, animated: false) }
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
        coordinator.calendars.release(picker)
    }

    final class Coordinator {
        var selection: Binding<Date>
        let calendars: TaskSelectionCalendars

        init(selection: Binding<Date>, calendars: TaskSelectionCalendars) {
            self.selection = selection
            self.calendars = calendars
        }

        @objc func changed(_ picker: UIDatePicker) { selection.wrappedValue = picker.date }
    }
}
