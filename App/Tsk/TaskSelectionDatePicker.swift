import SwiftUI
import UIKit
import TskCore

struct TaskSelectionDatePicker: View {
    let store: TaskStore
    let field: TaskDateField
    let calendars: TaskSelectionCalendars
    private let commonDateValue: String?
    private let originalDate: Date?
    @State private var referenceDay: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: TaskStore, field: TaskDateField, calendars: TaskSelectionCalendars) {
        self.store = store
        self.field = field
        self.calendars = calendars
        let tasks = store.selectionTasks
        let attribute = (field == .scheduled ? TaskRowParameter.scheduled : .deadline).attribute
        let first = tasks.first?.attributes[attribute]
        commonDateValue = tasks.allSatisfy { $0.attributes[attribute] == first } ? first : nil
        originalDate = field == .scheduled ? tasks.first?.plannedDate : tasks.first?.deadline
        let day = Calendar.autoupdatingCurrent.startOfDay(for: store.currentDate)
        _referenceDay = State(initialValue: day)
    }

    private var parameter: TaskRowParameter { field == .scheduled ? .scheduled : .deadline }
    private var includesTime: Bool {
        if case .exact(let intent) = store.selectionChanges[field] { return intent.hasTime }
        return false
    }

    private var minimumDate: Date? { field == .scheduled && !includesTime ? referenceDay : nil }

    private var selectedDate: Binding<Date> {
        Binding(get: {
            let edited = store.selectionChanges[field].flatMap { try? $0.resolvedDate(replacing: commonDateValue) }
            let date = edited ?? (commonDateValue == nil ? referenceDay : originalDate ?? referenceDay)
            return minimumDate.map { max($0, date) } ?? date
        }, set: { date in
            setDate(date, hasTime: includesTime)
        })
    }

    private func setDate(_ date: Date, hasTime: Bool) {
        let untimedDay = Calendar.autoupdatingCurrent.startOfDay(for: date)
        let value = hasTime ? date : field == .scheduled ? max(referenceDay, untimedDay) : untimedDay
        store.error = nil
        store.selectionChanges[field] = .exact(.init(date: value, hasTime: hasTime))
    }

    private func shortcut(to day: Date) -> TaskDateChange {
        let date = includesTime ? Calendar.autoupdatingCurrent.date(on: day, keepingTimeFrom: selectedDate.wrappedValue) : nil
        return .exact(.init(date: date ?? day, hasTime: includesTime))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(parameter.title, systemImage: parameter.symbol)
                Spacer()
                Button { store.selectionDateField = nil } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 32, height: 32)
                        .background(.primary.opacity(0.08), in: Circle())
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close " + parameter.title.lowercased() + " picker")
                .accessibilityIdentifier("close-selection-date")
            }
            TaskSelectionCalendar(calendars: calendars, field: field,
                                  selection: selectedDate.calendarDay(includesTime: includesTime), minimumDate: minimumDate)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Set time", isOn: Binding(get: { includesTime }, set: { setDate(selectedDate.wrappedValue, hasTime: $0) }))
                .font(.subheadline)
                .accessibilityIdentifier("selection-set-time")
            if includesTime {
                DatePicker("Time", selection: selectedDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("selection-time-picker")
            }
            HStack(spacing: 6) {
                Button { store.resetSelectionDate(field) } label: {
                    actionLabel("Reset", symbol: "arrow.counterclockwise", color: .orange)
                }
                .disabled(!store.selectionDateIsModified(field))
                .accessibilityLabel("Reset " + parameter.title.lowercased())
                .accessibilityIdentifier("reset-selection-date")
                choice("Remove", id: "remove", change: .remove, symbol: "trash", color: .red)
                choice("Today", id: "today", change: shortcut(to: referenceDay))
                if let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: referenceDay) {
                    choice("Tomorrow", id: "tomorrow", change: shortcut(to: tomorrow))
                }
            }
            .font(.caption.weight(.semibold))
            #if DEBUG
            .background {
                if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_MOTION"] == "1" {
                    TaskSelectionMotionProbe(operation: String(describing: store.selectionChanges[field]))
                }
            }
            #endif
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-date-picker")
        .accessibilityValue(store.selectionChanges[field].map(summary) ?? "Unchanged")
    }

    private func actionLabel(_ title: String, symbol: String? = nil, color: Color = .primary, selected: Bool = false) -> some View {
        Group {
            if let symbol { Image(systemName: symbol) }
            else { Text(title) }
        }
        .foregroundStyle(color)
        .frame(maxWidth: symbol == nil ? .infinity : nil)
        .frame(minWidth: 36, minHeight: 36)
        .background(color.opacity(selected ? 0.22 : 0.08), in: Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: selected)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func choice(_ title: String, id: String, change: TaskDateChange, symbol: String? = nil, color: Color = .primary) -> some View {
        let selected = store.selectionChanges[field] == change
        return Button {
            store.error = nil
            store.selectionChanges[field] = change
        } label: {
            actionLabel(title, symbol: symbol, color: color, selected: selected)
        }
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityLabel(id == "remove" ? "Remove " + parameter.title.lowercased() : title)
        .accessibilityIdentifier("selection-date-" + id)
    }

    private func summary(_ change: TaskDateChange) -> String {
        switch change {
        case .remove: "Remove \(parameter.title.lowercased()) when you tap Apply."
        case .day(let date): "\(date.formatted(date: .abbreviated, time: .omitted)). Existing times are kept. Tap Apply to save."
        case .set(let date): "\(date.formatted(date: .abbreviated, time: .shortened)). Tap Apply to save."
        case .exact(let intent): "\(intent.date.formatted(date: .abbreviated, time: intent.hasTime ? .shortened : .omitted)). Tap Apply to save."
        }
    }
}

#if DEBUG
private struct TaskSelectionMotionProbe: UIViewRepresentable {
    let operation: String

    func makeUIView(context: Context) -> Probe { Probe(frame: .zero) }
    func updateUIView(_ view: Probe, context: Context) { view.operation = operation }

    final class Probe: UIView {
        var operation = ""
        private var link: CADisplayLink?
        private var started: CFTimeInterval = 0
        private var changed: CFTimeInterval = 0
        private var lastOperation = ""
        private var previousY: CGFloat?
        private var baselineY: CGFloat = 0
        private var maximumDrift: CGFloat = 0
        private var changes = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "selection-picker-motion"
            accessibilityLabel = "Picker animation measurements"
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard window != nil else { return }
            started = CACurrentMediaTime()
            let display = CADisplayLink(target: self, selector: #selector(sample))
            display.add(to: .main, forMode: .common)
            link = display
        }

        @objc private func sample(_ display: CADisplayLink) {
            let presentation = layer.presentation() ?? layer
            let y = presentation.convert(presentation.bounds, to: nil).minY
            let ready = display.timestamp - started > 1
            if ready, operation != lastOperation, let previousY {
                baselineY = previousY
                changed = display.timestamp
                changes += 1
            }
            if ready, changed > 0, display.timestamp - changed < 0.8 {
                maximumDrift = max(maximumDrift, abs(y - baselineY))
            }
            lastOperation = operation
            previousY = y
            let proof: [String: Any] = ["ready": ready, "changes": changes, "maximumVerticalDrift": maximumDrift]
            if let data = try? JSONSerialization.data(withJSONObject: proof) {
                accessibilityValue = String(decoding: data, as: UTF8.self)
            }
        }
    }
}
#endif
