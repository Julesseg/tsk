import SwiftUI
import TskCore

struct TaskRowEditor: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    @FocusState.Binding var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredActionsHeight: CGFloat = 0
    @FocusState.Binding var focusedNote: UTF8String?
    let onActivate: () -> Void
    @Environment(\.taskRowActions) private var rowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                TaskRowEditorContent(store: store, editing: editing, focusedNote: $focusedNote,
                                     onActivate: onActivate)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("task-row-editor")
            .accessibilityAction(named: "Save and close task", rowActions.close)
            .accessibilityAction(.escape, rowActions.close)
            VStack(alignment: .leading, spacing: 8) {
                if let error = editing.error ?? store.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("draft-error")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if titleFocused || focusedNote != nil {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { titleFocused = false; focusedNote = nil }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier("dismiss-row-keyboard")
                }
            }
            .font(.subheadline)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredActionsHeight = $0 }
        }
        .frame(height: editing.revealProgress * min(measuredContentHeight + measuredActionsHeight, availableHeight), alignment: .top)
        .disabled(editing.isSaving || store.isSaving)
        .clipped()
        .buttonStyle(.borderless)
        .task(id: measuredContentHeight > 0) {
            guard measuredContentHeight > 0 else { return }
            await Task.yield()
            guard !Task.isCancelled, !editing.isExpanded, !editing.isSaving else { return }
            await editing.setExpanded(true, reduceMotion: reduceMotion)
        }
    }
}

private struct TaskRowEditorContent: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    @FocusState.Binding var focusedNote: UTF8String?
    let onActivate: () -> Void

    private var task: TaskRecord { editing.draft.original }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 0) {
                TaskRowPickerButton(editing: editing, parameter: .tags, tags: store.allTasks.flatMap(\.tags), onActivate: onActivate) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        firstLineReference.frame(width: 0)
                        VStack(alignment: .leading, spacing: 2) {
                            if editing.draft.taskDraft.tags.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "tag")
                                    Text("Tags")
                                }
                            } else {
                                ForEach(editing.draft.taskDraft.tags.map { UTF8String($0) }) { tag in
                                    Text(tag.rawValue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: .rect(cornerRadius: 4))
                                }
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: TaskSelectionRow.slotWidth, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
                TaskRowPriorityButton(editing: editing, onActivate: onActivate)
                VStack(alignment: .leading, spacing: 2) {
                    notes
                    project
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .disabled(!editing.isCapture && !task.canEdit)
            if task.recurrenceInspection != nil {
                TaskRecurrenceSection(task: task, store: store)
                    .padding(.vertical, 8)
            }
        }
        .disabled(editing.isSaving || store.isSaving)
    }

    private var firstLineReference: some View {
        Text(verbatim: " ").font(.subheadline).hidden().accessibilityHidden(true)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(task.annotations) { annotation in
                TextField("Notes", text: Binding(
                    get: { editing.draft.taskDraft.attributes[annotation.reference.rawValue] ?? "" },
                    set: { editing.draft.taskDraft.attributes[annotation.reference.rawValue] = $0 }
                ), axis: .vertical)
                .focused($focusedNote, equals: annotation.reference)
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("row-note-\(annotation.reference.rawValue)")
            }
            TextField("Notes", text: $editing.draft.noteInput, axis: .vertical)
                .focused($focusedNote, equals: UTF8String("new"))
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("row-note-input")
        }
        .textFieldStyle(.plain)
        .font(.subheadline)
        .lineLimit(1...5)
    }

    private var project: some View {
        let name = editing.draft.taskDraft.project
        let choices = Set((store.availableProjects + [name]).filter { !$0.isEmpty }.map { UTF8String($0) }).sorted()
        return Menu {
            Picker("Project", selection: Binding(
                get: { UTF8String(editing.draft.taskDraft.project) },
                set: { editing.draft.taskDraft.project = $0.rawValue }
            )) {
                Text("No project").tag(UTF8String(""))
                ForEach(choices) { Text($0.rawValue).tag($0) }
            }
            Button("New project…", systemImage: "folder.badge.plus") {
                onActivate()
                editing.parameter = .project
            }
            .accessibilityIdentifier("row-new-project")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                Text(name.isEmpty ? "Choose project" : name)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
            .background { TaskMenuActivation(action: onActivate).allowsHitTesting(false).accessibilityHidden(true) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .modifier(TaskRowPickerPresentation(editing: editing, parameter: .project))
    }
}

private struct TaskRowPriorityButton: View {
    @Bindable var editing: TaskRowEditing
    let onActivate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = editing.draft.taskDraft.priority
        Button {
            onActivate()
            editing.draft.taskDraft.priority = switch value {
            case "": "L"
            case "L": "M"
            case "M": "H"
            default: ""
            }
        } label: {
            Text(verbatim: " ")
                .font(.subheadline)
                .hidden()
                .frame(width: TaskSelectionRow.completionControlWidth)
                .overlay {
                    prioritySymbol(value)
                }
                .frame(width: TaskSelectionRow.completionControlWidth, height: 32, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Priority")
        .accessibilityValue(TaskRowParameter.priorityTitle(value))
        .accessibilityHint("Cycles through Low, Medium, High and None")
        .accessibilityIdentifier("row-priority")
    }

    private func prioritySymbol(_ value: String) -> some View {
        Group {
            switch value {
            case "": Image(systemName: "circle.fill").font(.system(size: 5))
            case "L": Image(systemName: "exclamationmark")
            case "M": Image(systemName: "exclamationmark.2")
            case "H": Image(systemName: "exclamationmark.3")
            default: Text(value).lineLimit(1)
            }
        }
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: value)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct TaskRowPickerButton<Label: View>: View {
    let editing: TaskRowEditing
    let parameter: TaskRowParameter
    var tags: [String] = []
    let onActivate: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            onActivate()
            editing.parameter = parameter
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskRowPickerPresentation(editing: editing, parameter: parameter, tags: tags))
        .disabled(editing.isSaving || !editing.isExpanded || !editing.isCapture && !editing.draft.original.canEdit)
    }
}

private struct TaskRowPickerPresentation: ViewModifier {
    let editing: TaskRowEditing
    let parameter: TaskRowParameter
    var tags: [String] = []
    @Namespace private var presentationNamespace

    func body(content: Content) -> some View {
        content
            .matchedTransitionSource(id: parameter.id, in: presentationNamespace)
            .popover(isPresented: Binding(
                get: { editing.parameter == parameter },
                set: { if !$0 && editing.parameter == parameter { editing.parameter = nil } }
            ), attachmentAnchor: .rect(.bounds)) {
                TaskRowParameterPicker(editing: editing, parameter: parameter, tags: tags, now: editing.referenceDate) { editing.parameter = nil }
                    .frame(idealWidth: 340, maxWidth: 340)
                    .navigationTransition(.zoom(sourceID: parameter.id, in: presentationNamespace))
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(parameter.title)
            .accessibilityValue(parameter.value(in: editing.draft.taskDraft) ?? "Not set")
            .accessibilityIdentifier("row-" + parameter.rawValue)
    }
}

struct TaskRowParameterPicker: View {
    @Environment(TaskURLController.self) private var automation
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let tags: [String]
    let dismiss: () -> Void
    private let today: Date
    @State private var original: TaskDraft
    @State private var contentHeight: CGFloat = 400
    @State private var tagError: String?

    init(editing: TaskRowEditing, parameter: TaskRowParameter, tags: [String], now: Date, dismiss: @escaping () -> Void) {
        self.editing = editing
        self.parameter = parameter
        self.tags = tags
        self.dismiss = dismiss
        today = Calendar.current.startOfDay(for: now)
        _original = State(initialValue: editing.draft.taskDraft)
    }

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealHeight: contentHeight, maxHeight: contentHeight)
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row-parameter-picker")
        .accessibilityAddTraits(.isModal)
        .modifier(TaskActionMessage(controller: automation))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading.fixedSize()
                    Spacer(minLength: 12)
                    doneButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    heading
                    doneButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            switch parameter {
            case .project:
                TextField("Project", text: $editing.draft.taskDraft.project)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("row-project-input")
            case .priority:
                EmptyView()
            case .tags:
                TaskRowTagsEditor(draft: $editing.draft, availableTags: tags, error: $tagError)
            case .scheduled, .deadline:
                dateControls
            }
        }
        .buttonStyle(.borderless)
        .padding(16)
    }

    private var field: TaskDateField { parameter == .scheduled ? .scheduled : .deadline }
    private var intent: TaskScheduledDate? { editing.draft.taskDraft.dateIntent(for: field) }
    private var hasTime: Bool { intent?.hasTime == true }

    private var selectedDate: Binding<Date> {
        Binding(get: {
            let date = intent?.date ?? today
            return field == .scheduled && !hasTime ? max(date, today) : date
        }, set: { setDate($0, hasTime: hasTime) })
    }

    private func setDate(_ date: Date, hasTime: Bool) {
        let day = Calendar.autoupdatingCurrent.startOfDay(for: date)
        let value = hasTime ? date : field == .scheduled ? max(day, today) : day
        editing.draft.taskDraft.setDateIntent(.init(date: value, hasTime: hasTime), for: field)
    }

    @ViewBuilder private var dateControls: some View {
        let day = selectedDate.calendarDay(includesTime: hasTime)
        DatePicker(parameter.title, selection: day, in: (field == .scheduled && !hasTime ? today : .distantPast)..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .accessibilityLabel(parameter.title)
            .accessibilityIdentifier(parameter.rawValue + "-picker")
        Toggle("Set time", isOn: Binding(get: { hasTime }, set: { setDate(selectedDate.wrappedValue, hasTime: $0) }))
            .accessibilityIdentifier(parameter.rawValue + "-has-time")
        if hasTime {
            DatePicker("Time", selection: selectedDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .accessibilityIdentifier(parameter.rawValue + "-time-picker")
        }
        HStack {
            Button("Reset", systemImage: "arrow.counterclockwise") {
                editing.draft.taskDraft.restoreDate(field, from: original)
                dismiss()
            }
            .labelStyle(.iconOnly)
            .disabled(original.dateIntent(for: field) == intent)
            Button("Remove " + parameter.title.lowercased(), systemImage: "trash", role: .destructive) {
                editing.draft.taskDraft.setDateIntent(nil, for: field)
                dismiss()
            }
            .labelStyle(.iconOnly)
            .disabled(editing.draft.taskDraft.attributes[parameter.attribute] == nil)
            .accessibilityIdentifier("remove-" + parameter.rawValue)
            Spacer()
            Button("Today") { day.wrappedValue = today }
            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) {
                Button("Tomorrow") { day.wrappedValue = tomorrow }
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
    }

    private var heading: some View {
        Label(parameter.title, systemImage: parameter.symbol).font(.headline)
            .accessibilityIdentifier("row-parameter-title")
    }

    private var doneButton: some View {
        Button("Done") {
            if parameter == .tags {
                do { try editing.draft.addTagInput() }
                catch { tagError = error.localizedDescription; return }
            } else if parameter != .project && parameter != .priority && parameter.date(in: editing.draft.taskDraft) == nil {
                setDate(selectedDate.wrappedValue, hasTime: hasTime)
            }
            dismiss()
        }
        .accessibilityIdentifier("close-row-parameter")
    }
}
