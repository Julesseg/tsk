import SwiftUI
import TskCore

struct TaskRowEditor: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    let namespace: Namespace.ID
    let close: () -> Void
    let information: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var titleFocused: Bool
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        TextField("What needs to be done?", text: $editing.draft.taskDraft.description, axis: .vertical)
                            .font(.subheadline)
                            .focused($titleFocused)
                            .matchedGeometryEffect(id: "title", in: namespace)
                            .accessibilityIdentifier("task-description")
                            .id("title")
                        Button(action: close) { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                            .accessibilityLabel("Save and collapse task")
                            .accessibilityIdentifier("collapse-task-row")
                    }
                    if !editing.draft.original.project.isEmpty {
                        Text(editing.draft.original.project).font(.caption).foregroundStyle(.secondary)
                            .matchedGeometryEffect(id: "project", in: namespace)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(TaskDateParameter.allCases) { parameter in
                                Button { titleFocused = false; editing.parameter = parameter } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(parameter.rawValue, systemImage: parameter.symbol).font(.caption)
                                        Text(parameterValue(parameter)).font(.subheadline)
                                    }
                                    .padding(10)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .modifier(TaskRowMorph(id: parameter == .deadline && editing.draft.original.deadline != nil ? "deadline" : parameter.id, namespace: namespace))
                                .accessibilityIdentifier("row-" + parameter.identifier)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("row-date-parameters")
                    .transition(.opacity)
                    TaskAvailabilityView(task: editing.draft.original, store: store)
                    if let error = editing.error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .accessibilityIdentifier("draft-error")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    HStack {
                        Button("More task information", systemImage: "info.circle", action: information)
                            .accessibilityIdentifier("task-row-information")
                        Spacer()
                        if titleFocused {
                            Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { titleFocused = false }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("dismiss-row-keyboard")
                        }
                    }.font(.subheadline)
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .disabled(editing.isSaving)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("task-row-editor")
            .onChange(of: titleFocused) { _, focused in if focused { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo("title", anchor: .top) } } }
        }
        .frame(height: min(contentHeight, availableHeight))
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: contentHeight)
        .taskKeyboardCommands(TaskEditorActions(save: close).keyboardCommands + [
            TaskKeyboardCommand(id: "collapse", input: "\u{1b}", modifiers: [], title: "Close Task Editor", action: close)
        ])
        .onChange(of: editing.isSaving) { _, saving in if saving { titleFocused = false } }
    }

    private func parameterValue(_ parameter: TaskDateParameter) -> String {
        let draft = editing.draft.taskDraft
        if let date = parameter.date(in: draft) { return date.formatted(date: .abbreviated, time: parameter == .planned ? .omitted : .shortened) }
        return draft.attributes[parameter.attribute] == nil ? "Add" : "Unrecognized date"
    }
}

struct TaskRowDatePicker: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskDateParameter
    let now: Date
    let availableHeight: CGFloat
    @State private var pickerHeight: CGFloat = 300
    @State private var choosingDay = false
    @State private var selectedDate: Date

    init(editing: TaskRowEditing, parameter: TaskDateParameter, now: Date, availableHeight: CGFloat) {
        self.editing = editing
        self.parameter = parameter
        self.now = now
        self.availableHeight = availableHeight
        _selectedDate = State(initialValue: parameter.date(in: editing.draft.taskDraft) ?? now)
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(parameter.rawValue).font(.headline)
                Spacer()
                Button("Done") { editing.parameter = nil }.accessibilityIdentifier("close-row-parameter")
            }
            if parameter == .planned {
                Button("Today") { editing.draft.plan(.today, now: now); editing.parameter = nil }.accessibilityIdentifier("plan-today")
                Button("Tomorrow") { editing.draft.plan(.tomorrow, now: now); editing.parameter = nil }.accessibilityIdentifier("plan-tomorrow")
                Button("Choose day") { choosingDay = true }.accessibilityIdentifier("choose-planned-day")
                if choosingDay {
                    datePicker
                    Button("Use displayed day") {
                        parameter.setDate(selectedDate, in: &editing.draft)
                        editing.parameter = nil
                    }
                }
                Button("Remove planned day", role: .destructive) { editing.draft.plan(.remove, now: now); editing.parameter = nil }
                    .accessibilityIdentifier("remove-planned-day")
            } else {
                datePicker
                Button("Use displayed date") {
                    parameter.setDate(selectedDate, in: &editing.draft)
                    editing.parameter = nil
                }.accessibilityIdentifier("use-parameter-date")
                Button("Remove " + parameter.rawValue.lowercased(), role: .destructive) {
                    editing.draft.taskDraft.attributes[parameter.attribute] = nil
                    editing.parameter = nil
                }.accessibilityIdentifier("remove-" + parameter.identifier)
            }
        }
        .buttonStyle(.borderless)
        .padding()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 420)
        .frame(height: min(pickerHeight, availableHeight))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row-parameter-picker")
        .accessibilityAddTraits(.isModal)
    }

    private var datePicker: some View {
        DatePicker(parameter.rawValue, selection: $selectedDate,
                   displayedComponents: parameter == .planned ? [.date] : [.date, .hourAndMinute])
        .onChange(of: selectedDate) { _, date in parameter.setDate(date, in: &editing.draft) }
        .datePickerStyle(.wheel)
        .labelsHidden()
        .accessibilityIdentifier(parameter.identifier + "-picker")

    }
}
