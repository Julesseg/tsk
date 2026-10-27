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
                                                 projects: store.availableProjects, now: editing.referenceDate) {
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
        .padding(.bottom, 8)
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
                .simultaneousGesture(TapGesture().onEnded {
                    unfocus()
                    traceTaskRowMenuHitTests(parameter: parameter, editing: editing)
                })
            } else {
                Button(action: openPicker) { label }
            }
        }
        .buttonStyle(TaskRowParameterButtonStyle())
        .matchedTransitionSource(id: parameter.id, in: presentationNamespace)
        .popover(isPresented: Binding(
            get: { editing.parameter == parameter },
            set: {
                traceTaskRowMenu("popover binding \(parameter.rawValue)=\($0)", editing: editing)
                if !$0 && editing.parameter == parameter { editing.parameter = nil }
            }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            TaskRowParameterPicker(editing: editing, parameter: parameter, now: now) { editing.parameter = nil }
                .frame(width: 340)
                .navigationTransition(.zoom(sourceID: parameter.id, in: presentationNamespace))
                .presentationCompactAdaptation(.popover)
                .onAppear { traceTaskRowMenu("picker appeared \(parameter.rawValue)", editing: editing) }
                .onDisappear { traceTaskRowMenu("picker disappeared \(parameter.rawValue)", editing: editing) }
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
        traceTaskRowMenu("openPicker entered \(parameter.rawValue)", editing: editing)
        unfocus()
        editing.parameter = parameter
        traceTaskRowMenu("openPicker assigned \(parameter.rawValue)", editing: editing)
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
        HStack(spacing: 5) {
            Image(systemName: parameter.symbol).font(.caption)
            if let value {
                Text(value).lineLimit(1)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

private struct TaskRowParameterButtonStyle: ButtonStyle {
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

@MainActor
func traceTaskRowMenuHitTests(parameter: TaskRowParameter, editing: TaskRowEditing) {
#if DEBUG
    guard ProcessInfo.processInfo.environment["TSK_TEST_MENU_PROBE"] == "1" else { return }
    traceTaskRowMenu("menu label tapped \(parameter.rawValue)", editing: editing)
    Task { @MainActor [weak editing] in
        for delay in [0.5, 0.5, 1.0, 2.0, 2.0, 2.0] {
            try? await Task.sleep(for: .seconds(delay))
            guard let editing, editing.isExpanded else { return }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            var count = 0
            for window in windows {
                var pending: [UIView] = [window]
                var visited = 0
                while let view = pending.popLast(), visited < 10_000 {
                    visited += 1
                    pending.append(contentsOf: view.subviews)
                    guard let cell = view as? UICollectionViewCell,
                          String(describing: type(of: cell)).contains("ContextMenu") else { continue }
                    count += 1
                    guard count <= 30 else { continue }
                    let center = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window)
                    guard center.x.isFinite, center.y.isFinite else { continue }
                    let hit = window.hitTest(center, with: nil)
                    var chain: [String] = []
                    var ancestor = hit
                    while let current = ancestor, chain.count < 12 {
                        chain.append(String(describing: type(of: current)))
                        ancestor = current.superview
                    }
                    print("[TSK61-MENU-HIT-PROBE] time=\(CACurrentMediaTime()) parameter=\(parameter.rawValue) center=\(center) cell=\(cell.convert(cell.bounds, to: window)) hidden=\(cell.isHidden) alpha=\(cell.alpha) interactive=\(cell.isUserInteractionEnabled) window=\(type(of: window)) level=\(window.windowLevel.rawValue) hitInsideCell=\(hit?.isDescendant(of: cell) ?? false) chain=\(chain)")
                }
            }
            print("[TSK61-MENU-HIT-PROBE] time=\(CACurrentMediaTime()) parameter=\(parameter.rawValue) cells=\(count)")
        }
    }
#endif
}

@MainActor
func traceTaskRowMenu(_ event: String, editing: TaskRowEditing) {
#if DEBUG
    guard ProcessInfo.processInfo.environment["TSK_TEST_MENU_PROBE"] == "1" else { return }
    print("[TSK61-MENU-PROBE] event=\(event) editing=\(ObjectIdentifier(editing)) parameter=\(editing.parameter?.rawValue ?? "nil") expanded=\(editing.isExpanded) saving=\(editing.isSaving)")
#endif
}

@MainActor
func traceTaskRowAnimationWait(editing: TaskRowEditing) {
#if DEBUG
    guard ProcessInfo.processInfo.environment["TSK_TEST_MENU_PROBE"] == "1" else { return }
    Task { @MainActor [weak editing] in
        for delay in [2, 8, 60] {
            try? await Task.sleep(for: .seconds(delay))
            guard let editing else { return }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            var visited = 0
            var active = 0
            func inspect(_ layer: CALayer, path: String) {
                guard visited < 10_000 else { return }
                visited += 1
                for key in layer.animationKeys() ?? [] {
                    guard let animation = layer.animation(forKey: key) else { continue }
                    active += 1
                    guard active <= 200 else { continue }
                    print("[TSK61-ANIMATION-PROBE] path=\(path) owner=\(layer.delegate.map { String(describing: type(of: $0)) } ?? "nil") key=\(key) type=\(type(of: animation)) duration=\(animation.duration) repeat=\(animation.repeatCount) repeatDuration=\(animation.repeatDuration) speed=\(animation.speed) begin=\(animation.beginTime) removed=\(animation.isRemovedOnCompletion) keyPath=\((animation as? CAPropertyAnimation)?.keyPath ?? "nil")")
                }
                for (index, child) in (layer.sublayers ?? []).enumerated() {
                    inspect(child, path: path + "/" + String(index))
                }
            }
            for (index, window) in windows.enumerated() {
                print("[TSK61-ANIMATION-PROBE] window=\(index) type=\(type(of: window)) screen=\(ObjectIdentifier(window.screen)) hidden=\(window.isHidden) key=\(window.isKeyWindow)")
                inspect(window.layer, path: String(index))
            }
            print("[TSK61-ANIMATION-PROBE] elapsed=\(CACurrentMediaTime()) visited=\(visited) active=\(active) rowAnimating=\(editing.isAnimating) expanded=\(editing.isExpanded) progress=\(editing.revealProgress) parameter=\(editing.parameter?.rawValue ?? "nil")")
        }
    }
#endif
}
