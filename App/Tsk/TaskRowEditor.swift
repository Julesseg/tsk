import SwiftUI
import TskCore

struct TaskRowEditor: View {
    let store: TaskStore
    @Bindable var editing: TaskRowEditing
    @FocusState.Binding var titleFocused: Bool
    let information: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @Namespace private var namespace
    @State private var measuredContentHeight: CGFloat = 0
    @State private var revealProgress: CGFloat = 0
    @State private var parameterViewport = CGRect.zero

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(height: revealProgress * min(measuredContentHeight, availableHeight), alignment: .top)
        .clipped()
        .task(id: editing.isExpanded) {
            let target: CGFloat = editing.isExpanded ? 1 : 0
            guard !reduceMotion else { revealProgress = target; return }
            let initial = revealProgress
            let start = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let fraction = min(1, seconds / 0.28)
                let eased = fraction * fraction * (3 - 2 * fraction)
                withTransaction(Transaction(animation: nil)) {
                    revealProgress = initial + (target - initial) * eased
                }
                if fraction == 1 { return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-editor")
        .task(id: measuredContentHeight > 0) {
            guard measuredContentHeight > 0 else { return }
            await Task.yield()
            guard !Task.isCancelled, !editing.isExpanded, !editing.isSaving else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { editing.isExpanded = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(TaskRowParameter.allCases) { parameter in
                            TaskRowParameterPill(editing: editing, parameter: parameter, viewport: parameterViewport,
                                                 projects: store.availableProjects,
                                                 namespace: namespace) {
                                titleFocused = false
                            }
                        }
                    }.padding(4)
                }
            }
            .scrollIndicators(.hidden)
            .clipped()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { parameterViewport = $0 }
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
    let viewport: CGRect
    let projects: [String]
    let namespace: Namespace.ID
    let unfocus: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounds = CGRect.zero

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
        .buttonStyle(.plain)
        .accessibilityLabel(parameter.title)
        .accessibilityValue(value ?? "Not set")
        .accessibilityIdentifier("row-" + parameter.identifier)
        .onChange(of: viewport) { _, _ in
            if editing.parameter == parameter && !editing.parameterClosing { updateSource() }
        }
    }

    private var label: some View {
        TaskRowParameterLabel(parameter: parameter, value: parameter.value(in: editing.draft.taskDraft))
            .glassEffect(editing.parameter == parameter ? .identity : .regular.interactive(), in: Capsule())
            .glassEffectID(editing.parameter == parameter ? nil : parameter.id, in: namespace)
            .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
            .opacity(editing.parameter == parameter ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                bounds = $0
                if editing.parameter == parameter && !editing.parameterClosing { updateSource() }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 44)
            .contentShape(Rectangle())
    }

    private func openPicker() {
        unfocus()
        updateSource()
        editing.parameterAnchor = editing.parameterSource
        editing.parameterExpanded = false
        editing.parameterClosing = false
        editing.parameter = parameter
    }

    private func updateSource() {
        let visible = bounds.intersection(viewport)
        guard !visible.isEmpty && !visible.isNull else { return }
        editing.parameterBounds = bounds
        editing.parameterSource = visible
    }
}

struct TaskRowParameterPicker: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let availableHeight: CGFloat
    let ready: () -> Void
    let dismiss: () -> Void
    @State private var selectedDate: Date
    @State private var measuredContentHeight: CGFloat = 0

    init(editing: TaskRowEditing, parameter: TaskRowParameter, now: Date, availableHeight: CGFloat, ready: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.editing = editing
        self.parameter = parameter
        self.availableHeight = availableHeight
        self.ready = ready
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
        .task(id: measuredContentHeight > 0) {
            guard measuredContentHeight > 0 else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            ready()
        }
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

struct TaskRowPickerSurface: View {
    @Bindable var editing: TaskRowEditing
    let parameter: TaskRowParameter
    let origin: CGPoint
    let size: CGSize
    let now: Date
    let dismiss: () -> Void
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let source = editing.parameterSource.offsetBy(dx: -origin.x, dy: -origin.y)
        let anchor = editing.parameterAnchor.offsetBy(dx: -origin.x, dy: -origin.y)
        let pill = editing.parameterBounds.offsetBy(dx: -editing.parameterSource.minX, dy: -editing.parameterSource.minY)
        let width = min(360, size.width - 32)
        let height = min(contentHeight, max(120, size.height - 32))
        let x = min(max(16, anchor.midX - width / 2), size.width - width - 16)
        let below = anchor.maxY + 8
        let preferredY = below + height <= size.height - 16 ? below : anchor.minY - height - 8
        let y = min(max(16, preferredY), size.height - height - 16)
        let expanded = editing.parameterExpanded
        ZStack(alignment: .topLeading) {
            TaskRowParameterPicker(editing: editing, parameter: parameter,
                                   now: now, availableHeight: max(120, size.height - 32), ready: {
                guard editing.parameter == parameter, !expanded, !editing.parameterClosing else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { editing.parameterExpanded = true }
            }, dismiss: dismiss)
                .frame(width: width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .opacity(expanded ? 1 : 0)
                .accessibilityHidden(!expanded)
            TaskRowParameterLabel(parameter: parameter, value: parameter.value(in: editing.draft.taskDraft))
                .frame(width: pill.width, height: pill.height)
                .offset(x: pill.minX, y: pill.minY)
                .opacity(expanded ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(width: expanded ? width : source.width, height: expanded ? height : source.height, alignment: .topLeading)
        .clipped()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: expanded ? 24 : 16))
        .position(x: expanded ? x + width / 2 : source.midX,
                  y: expanded ? y + height / 2 : source.midY)
        .allowsHitTesting(expanded)
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
        .padding(.horizontal, 10)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Capsule())
    }
}
