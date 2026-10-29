import SwiftUI
import TskCore

struct TaskRowEditor: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    @FocusState.Binding var titleFocused: Bool
    let information: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredActionsHeight: CGFloat = 44
    @State private var linkedTask: TaskRecord?
    @FocusState private var focusedNote: UTF8String?
    @Environment(\.taskRowActions) private var rowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                TaskRowEditorContent(store: store, editing: editing, titleFocused: $titleFocused, focusedNote: $focusedNote)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("task-row-supporting-scroll")
            VStack(alignment: .leading, spacing: 8) {
                if editing.supportingPanel == nil, let error = editing.error ?? store.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("draft-error")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                HStack(alignment: .top) {
                    Button("More task information", systemImage: "info.circle", action: information)
                        .accessibilityIdentifier("task-row-information")
                    Spacer()
                    Button("Save and close", systemImage: "checkmark", action: rowActions.close)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44, alignment: .top)
                        .accessibilityIdentifier("collapse-task-row")
                    if titleFocused || focusedNote != nil {
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { titleFocused = false; focusedNote = nil }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44, alignment: .top)
                            .accessibilityIdentifier("dismiss-row-keyboard")
                    }
                }
            }
            .font(.subheadline)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredActionsHeight = $0 }
        }
        .frame(height: editing.revealProgress * min(measuredContentHeight + measuredActionsHeight + 8, availableHeight), alignment: .top)
        .disabled(editing.isSaving || store.isSaving)
        .clipped()
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-editor")
        .sheet(item: $editing.supportingPanel, onDismiss: {
            store.error = nil
            if let target = linkedTask { linkedTask = nil; rowActions.reveal(target) }
        }) { panel in
            switch panel {
            case .dependency:
                TaskDependencySelection(store: store, task: editing.draft.original, onSave: editing.absorb) { target in
                    linkedTask = target
                    editing.supportingPanel = nil
                }
            case .attributes:
                TaskAdvancedAttributesEditor(store: store, task: editing.draft.original, onSave: editing.absorb)
            }
        }
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
    @FocusState.Binding var titleFocused: Bool
    @FocusState.Binding var focusedNote: UTF8String?

    private var task: TaskRecord { editing.draft.original }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .padding(.bottom, 4)
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(TaskRowParameter.allCases) { parameter in
                            TaskRowParameterPill(editing: editing, parameter: parameter,
                                                 projects: store.availableProjects,
                                                 tags: store.allTasks.flatMap(\.tags), now: editing.referenceDate) {
                                titleFocused = false
                                focusedNote = nil
                            }
                        }
                        Button { open(.dependency) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.branch")
                                if !task.dependencyReferences.isEmpty { Text(task.dependencyReferences.count, format: .number) }
                            }
                            .font(.caption)
                        }
                        .buttonStyle(TaskRowParameterButtonStyle())
                        .frame(minWidth: 44, minHeight: 44, alignment: .top)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Dependencies")
                        .accessibilityValue("\(task.dependencyReferences.count) dependencies")
                        .accessibilityIdentifier("row-dependencies")
                        TaskActivityButton(task: task, store: store, isDetail: true, isPill: true, onSave: editing.absorb)
                    }.padding(.horizontal, 4)
                }
            }
            .scrollIndicators(.hidden)
            .clipped()
            .accessibilityIdentifier("row-date-parameters")
            .transition(.opacity)
            VStack(alignment: .leading, spacing: 12) {
                TaskAvailabilityView(task: task, store: store)
                TaskAdvancedAttributesSection(store: store, task: task, edit: { open(.attributes) })
                TaskRecurrenceSection(task: task, store: store)
            }
            .padding(.vertical, 8)

        }
        .padding(.bottom, 8)
        .disabled(editing.isSaving || store.isSaving)
    }

    private func open(_ panel: TaskRowEditing.SupportingPanel) {
        titleFocused = false
        focusedNote = nil
        editing.error = nil
        store.error = nil
        editing.supportingPanel = panel
    }
}

private struct TaskRowParameterPill: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let projects: [String]
    let tags: [String]
    let now: Date
    let unfocus: () -> Void
    @Namespace private var presentationNamespace

    var body: some View {
        let value = parameter.value(in: editing.draft.taskDraft)
        Group {
            if parameter == .project || parameter == .priority {
                Menu {
                    if parameter == .project {
                        Picker("Project", selection: Binding(
                            get: { UTF8String(editing.draft.taskDraft.project) },
                            set: { editing.draft.taskDraft.project = $0.rawValue }
                        )) {
                            Text("No project").tag(UTF8String(""))
                            ForEach(Set((projects + [editing.draft.taskDraft.project]).filter { !$0.isEmpty }.map { UTF8String($0) }).sorted(), id: \.self) { project in
                                Text(project.rawValue).tag(project)
                            }
                        }
                        Button("New project…", systemImage: "folder.badge.plus", action: openPicker)
                            .accessibilityIdentifier("row-new-project")
                    } else {
                        Picker("Priority", selection: $editing.draft.taskDraft.priority) {
                            ForEach(["", "L", "M", "H"], id: \.self) { priority in
                                Text(TaskRowParameter.priorityTitle(priority)).tag(priority)
                            }
                            if !["", "L", "M", "H"].contains(editing.draft.taskDraft.priority) {
                                Text(editing.draft.taskDraft.priority).tag(editing.draft.taskDraft.priority)
                            }
                        }
                    }
                } label: {
                    label
                }
                .simultaneousGesture(TapGesture().onEnded { unfocus() })
            } else {
                Button(action: openPicker) { label }
            }
        }
        .buttonStyle(TaskRowParameterButtonStyle())
        .matchedTransitionSource(id: parameter.id, in: presentationNamespace)
        .popover(isPresented: Binding(
            get: { editing.parameter == parameter },
            set: { if !$0 && editing.parameter == parameter { editing.parameter = nil } }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            TaskRowParameterPicker(editing: editing, parameter: parameter, tags: tags, now: now) { editing.parameter = nil }
                .frame(width: 340)
                .navigationTransition(.zoom(sourceID: parameter.id, in: presentationNamespace))
                .presentationCompactAdaptation(.popover)
        }
        .frame(minWidth: 44, minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityLabel(parameter.title)
        .accessibilityValue(value ?? "Not set")
        .accessibilityIdentifier("row-" + parameter.identifier)
    }

    private var label: some View {
        TaskRowParameterLabel(parameter: parameter, value: parameter.value(in: editing.draft.taskDraft))
    }

    private func openPicker() {
        unfocus()
        editing.parameter = parameter
    }
}

struct TaskRowParameterPicker: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let tags: [String]
    let dismiss: () -> Void
    @State private var selectedDate: Date
    @State private var contentHeight: CGFloat = 400
    @State private var tagError: String?

    init(editing: TaskRowEditing, parameter: TaskRowParameter, tags: [String], now: Date, dismiss: @escaping () -> Void) {
        self.editing = editing
        self.parameter = parameter
        self.tags = tags
        self.dismiss = dismiss
        _selectedDate = State(initialValue: parameter.date(in: editing.draft.taskDraft) ?? now)
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
            default:
                DatePicker(parameter.title, selection: $selectedDate,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .onChange(of: selectedDate) { _, date in parameter.setDate(date, in: &editing.draft) }
                    .accessibilityIdentifier(parameter.identifier + "-picker")
            }
            if parameter != .tags && editing.draft.taskDraft.attributes[parameter.attribute] != nil {
                Button("Remove " + parameter.title.lowercased(), role: .destructive) {
                    editing.draft.taskDraft.attributes[parameter.attribute] = nil
                    dismiss()
                }
                .accessibilityIdentifier("remove-" + parameter.identifier)
            }
        }
        .buttonStyle(.borderless)
        .padding(16)
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
                parameter.setDate(selectedDate, in: &editing.draft)
            }
            dismiss()
        }
        .accessibilityIdentifier("close-row-parameter")
    }
}

struct TaskRowParameterLabel: View {
    let parameter: TaskRowParameter
    let value: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: parameter.symbol).font(.caption)
            if let value {
                Text(value).lineLimit(1).frame(maxWidth: 220)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

struct TaskRowParameterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
            .background(.background, in: Capsule())
            .overlay { Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
