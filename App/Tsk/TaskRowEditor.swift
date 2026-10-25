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

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(height: editing.revealProgress * min(measuredContentHeight, availableHeight), alignment: .top)
        .clipped()
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-editor")
        .task(id: measuredContentHeight > 0) {
            guard measuredContentHeight > 0 else { return }
            await Task.yield()
            guard !Task.isCancelled, !editing.isExpanded, !editing.isSaving else { return }
            await editing.setExpanded(true, reduceMotion: reduceMotion)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(TaskRowParameter.allCases) { parameter in
                            TaskRowParameterPill(editing: editing, parameter: parameter,
                                                 projects: store.availableProjects, now: store.currentDate) {
                                titleFocused = false
                            }
                        }
                    }.padding(4)
                }
            }
            .scrollIndicators(.hidden)
            .clipped()
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
        .padding(.top, 8)
        .padding(.bottom, 12)
        .disabled(editing.isSaving)
    }
}

private struct TaskRowParameterPill: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let projects: [String]
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
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .matchedTransitionSource(id: parameter.id, in: presentationNamespace)
        .popover(isPresented: Binding(
            get: { editing.parameter == parameter },
            set: { if !$0 && editing.parameter == parameter { editing.parameter = nil } }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            TaskRowParameterPicker(editing: editing, parameter: parameter, now: now) { editing.parameter = nil }
                .frame(width: 340)
                .navigationTransition(.zoom(sourceID: parameter.id, in: presentationNamespace))
                .presentationCompactAdaptation(.popover)
        }
        .frame(minWidth: 44, minHeight: 44)
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
    let dismiss: () -> Void
    @State private var selectedDate: Date
    @State private var contentHeight: CGFloat = 400

    init(editing: TaskRowEditing, parameter: TaskRowParameter, now: Date, dismiss: @escaping () -> Void) {
        self.editing = editing
        self.parameter = parameter
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
            HStack {
                Label(parameter.title, systemImage: parameter.symbol).font(.headline)
                Spacer()
                Button("Done") {
                    if parameter != .project && parameter != .priority && parameter.date(in: editing.draft.taskDraft) == nil {
                        parameter.setDate(selectedDate, in: &editing.draft)
                    }
                    dismiss()
                }
                .accessibilityIdentifier("close-row-parameter")
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
            default:
                DatePicker(parameter.title, selection: $selectedDate,
                           displayedComponents: parameter == .scheduled ? [.date] : [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .onChange(of: selectedDate) { _, date in parameter.setDate(date, in: &editing.draft) }
                    .accessibilityIdentifier(parameter.identifier + "-picker")
            }
            if editing.draft.taskDraft.attributes[parameter.attribute] != nil {
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
}

struct TaskRowParameterLabel: View {
    let parameter: TaskRowParameter
    let value: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: parameter.symbol)
            if let value {
                Text(value).lineLimit(1)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}
