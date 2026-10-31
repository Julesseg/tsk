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
            TaskRowEditorContent(store: store, editing: editing, titleFocused: $titleFocused, information: information)
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
}

private struct TaskRowEditorContent: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    @FocusState.Binding var titleFocused: Bool
    let information: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(TaskRowParameter.allCases) { parameter in
                            TaskRowParameterPill(editing: editing, parameter: parameter,
                                                 projects: store.availableProjects,
                                                 tags: store.allTasks.flatMap(\.tags), now: editing.referenceDate) {
                                titleFocused = false
                            }
                        }
                    }.padding(.horizontal, 4)
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
            HStack(alignment: .top) {
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
        .padding(.bottom, 8)
        .disabled(editing.isSaving)
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
                TaskRowMenuButton(editing: editing, parameter: parameter, projects: projects,
                                  unfocus: unfocus, openPicker: openPicker)
                    .fixedSize()
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

struct TaskRowParameterPillAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
            .background(.background, in: Capsule())
            .overlay { Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 1) }
    }
}

private struct TaskRowParameterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(TaskRowParameterPillAppearance())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
