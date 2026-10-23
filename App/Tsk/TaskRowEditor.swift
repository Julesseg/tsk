import SwiftUI
import TskCore

struct TaskRowEditor: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    let namespace: Namespace.ID
    let close: () -> Void
    let information: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @Environment(\.taskRowActions) private var rowActions
    @FocusState private var titleFocused: Bool
    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if measuredContentHeight == 0 { withAnimation(nil) { measuredContentHeight = height } }
                        else { withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { measuredContentHeight = height } }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: titleFocused) { _, focused in
                if focused { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo("title", anchor: .top) } }
            }
        }
        .frame(height: min(max(measuredContentHeight, 44 + 24), availableHeight))
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-editor")
        .taskKeyboardCommands(TaskEditorActions(save: close).keyboardCommands + [
            TaskKeyboardCommand(id: "collapse", input: "\u{1b}", modifiers: [], title: "Close Task Editor", action: close)
        ])
        .onChange(of: editing.isSaving) { _, saving in if saving { titleFocused = false } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                TextField("What needs to be done?", text: $editing.draft.taskDraft.description, axis: .vertical)
                    .font(.subheadline)
                    .focused($titleFocused)
                    .matchedGeometryEffect(id: "title", in: namespace, properties: .position)
                    .accessibilityIdentifier("task-description")
                    .id("title")
                Button(action: close) { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                    .accessibilityLabel("Save and collapse task")
                    .accessibilityIdentifier("collapse-task-row")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(TaskRowParameter.allCases) { parameter in
                        TaskRowParameterPill(editing: editing, parameter: parameter,
                                             namespace: rowActions.glassNamespace ?? namespace, rowNamespace: namespace) {
                            titleFocused = false
                        }
                    }
                }.padding(4)
            }
            .scrollIndicators(.hidden)
            .compositingGroup()
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
        .padding(12)
        .disabled(editing.isSaving)
    }
}

private struct TaskRowParameterPill: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let namespace: Namespace.ID
    let rowNamespace: Namespace.ID
    let unfocus: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounds = CGRect.zero

    var body: some View {
        let value = parameter.value(in: editing.draft.taskDraft)
        Button {
            unfocus()
            editing.parameterSource = bounds
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { editing.parameter = parameter }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: parameter.symbol)
                if let value {
                    Text(value).lineLimit(1)
                        .modifier(TaskRowMorph(id: parameter.rawValue, namespace: parameter == .project && !editing.draft.original.project.isEmpty || parameter == .deadline && editing.draft.original.deadline != nil ? rowNamespace : nil))
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(editing.parameter != nil ? .identity : .regular.interactive(), in: Capsule())
        .glassEffectID(editing.parameter != nil ? nil : parameter.id, in: namespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .opacity(editing.parameter != nil ? 0 : 1)
        .accessibilityLabel(parameter.title)
        .accessibilityValue(value ?? "Not set")
        .accessibilityIdentifier("row-" + parameter.identifier)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds = $0 }
    }
}

struct TaskRowParameterPicker: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let projects: [String]
    let now: Date
    let availableHeight: CGFloat
    let dismiss: () -> Void
    @State private var selectedDate: Date
    @State private var measuredContentHeight: CGFloat = 0

    init(editing: TaskRowEditing, parameter: TaskRowParameter, projects: [String], now: Date, availableHeight: CGFloat, dismiss: @escaping () -> Void) {
        self.editing = editing
        self.parameter = parameter
        self.projects = projects
        self.now = now
        self.availableHeight = availableHeight
        self.dismiss = dismiss
        _selectedDate = State(initialValue: parameter.date(in: editing.draft.taskDraft) ?? now)
    }

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(measuredContentHeight, availableHeight))
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
                ForEach(projects.prefix(5), id: \.self) { project in
                    Button(project) { editing.draft.taskDraft.project = project; dismiss() }
                }
            case .priority:
                ForEach(["", "L", "M", "H"], id: \.self) { priority in
                    Button {
                        editing.draft.taskDraft.priority = priority
                        dismiss()
                    } label: {
                        HStack {
                            Text(TaskRowParameter.priorityTitle(priority))
                            Spacer()
                            if editing.draft.taskDraft.priority == priority { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("row-priority-" + (priority.isEmpty ? "none" : priority))
                }
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

struct TaskRowPickerLayout: Layout {
    let source: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let picker = subviews.first else { return }
        let width = min(360, bounds.width - 32)
        let size = picker.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let height = min(size.height, bounds.height - 32)
        let x = min(max(bounds.minX + 16, source.midX - width / 2), bounds.maxX - width - 16)
        let below = source.maxY + 8
        let preferredY = below + height <= bounds.maxY - 16 ? below : source.minY - height - 8
        let y = min(max(bounds.minY + 16, preferredY), bounds.maxY - height - 16)
        picker.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
    }
}
