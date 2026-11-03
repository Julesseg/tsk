import SwiftUI
import UIKit
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let selection: Binding<UUID?>?
    let calendar: TodayCalendarController
    let edit: (TaskRecord) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardFrame = CGRect.null

    var body: some View {
        GeometryReader { geometry in
        let keyboardInset = keyboardOverlap(in: geometry.frame(in: .global))
        Group {
            if store.customView == nil && store.query == .today {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        TodayCalendarSection(calendar: calendar)
                        Section {
                            if let error = store.error, store.visibleTasks.isEmpty { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                            else if store.visibleTasks.isEmpty { Text("Nothing planned or due today").foregroundStyle(.secondary) }
                            ForEach(store.visibleTasks) { task in TaskListRow(task: task, store: store, edit: edit) }
                        }
                        .listSectionSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }.accessibilityIdentifier("task-list")
                        .refreshable { await store.reload(); await calendar.refresh() }
                        .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                        .task(id: store.rowEditing?.rowID) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                        .task(id: store.rowEditing?.isAnimating) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                        .task(id: geometry.size.height - keyboardInset) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                }
            } else if let error = store.error, store.visibleTasks.isEmpty {
                ContentUnavailableView {
                    Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await store.reload() } }
                }
            } else if store.visibleTasks.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "checklist", description: Text(store.customView != nil ? "Edit the filter or choose another view to find tasks." : "Capture a task to get started. Saved tasks stay on this device when you're offline."))
            } else if store.customView == nil && store.query == .upcoming {
                UpcomingTaskList(store: store, selection: selection, edit: edit, viewport: CGRect(origin: geometry.frame(in: .global).origin, size: CGSize(width: geometry.size.width, height: geometry.size.height - keyboardInset)))
            } else {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        ForEach(store.visibleTasks) { task in
                            TaskListRow(task: task, store: store, edit: edit)
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    .refreshable { await store.reload() }
                    .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                    .task(id: store.rowEditing?.rowID) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: store.rowEditing?.isAnimating) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: geometry.size.height - keyboardInset) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                }
            }
        }
        .modifier(TaskRowFocusOffset(editing: store.rowEditing))
        .transaction { if store.rowEditing != nil { $0.animation = nil } }
        .safeAreaPadding(.bottom, store.rowEditing == nil ? 0 : keyboardInset)
        .environment(\.taskRowAvailableHeight, max(120, geometry.size.height - keyboardInset - 24))
        .environment(\.taskRowViewport, geometry.frame(in: .global))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.completionFeedback.removingIDs(context: store.completionContext))
        .environment(\.defaultMinListRowHeight, 0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .overlay { if store.isLoading && store.visibleTasks.isEmpty { ProgressView() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardFrame = .null }
    }

    private func keyboardOverlap(in bounds: CGRect) -> CGFloat {
        guard !keyboardFrame.isNull, keyboardFrame.intersects(bounds), keyboardFrame.maxY >= bounds.maxY else { return 0 }
        return max(0, bounds.maxY - keyboardFrame.minY)
    }

    private func editorIsClipped(in viewport: CGRect, keyboardInset: CGFloat) -> Bool {
        guard let editing = store.rowEditing, !editing.isAnimating, editing.visibilityBounds != .zero else { return false }
        return editing.visibilityBounds.minY < viewport.minY - 1 || editing.visibilityBounds.maxY > viewport.maxY - keyboardInset + 1
    }

    private func revealEditor(using proxy: ScrollViewProxy, viewport: CGRect, keyboardInset: CGFloat) {
        guard !Task.isCancelled, editorIsClipped(in: viewport, keyboardInset: keyboardInset), let editing = store.rowEditing else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            proxy.scrollTo(editing.draft.original.id, anchor: .top)
        }
    }

    private var emptyTitle: String {
        if store.customView != nil { return "No matching tasks" }
        switch store.query {
        case .upcoming: return "No upcoming plans or deadlines"
        case .today: return "Nothing planned or due today"
        case .completed: return "No completed tasks"
        default: return "No unfinished tasks"
        }
    }
}

struct TaskListMetadata: View {
    let task: TaskRecord
    let store: TaskStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !task.project.isEmpty {
                Text(task.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                TaskPlanningCaption(task: task, today: store.currentDate)
                    .multilineTextAlignment(.trailing)
            }
            .layoutPriority(1)
        }
    }
}

struct TaskListRow: View {
    let task: TaskRecord
    let store: TaskStore
    let edit: (TaskRecord) -> Void
    var rowIdentifier: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @FocusState private var titleFocused: Bool
    @State private var headerHeight: CGFloat = 44
    @State private var titleHeight: CGFloat = 44
    @State private var rowGeometry = TaskRowGeometry()
    @ScaledMetric(relativeTo: .subheadline) private var titleLineHeight: CGFloat = 20
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @Environment(\.taskRowViewport) private var viewport
    @Environment(\.taskRowActions) private var rowActions
    private var identity: String { rowIdentifier ?? "task-" + task.id.uuidString }
    private var editing: TaskRowEditing? { store.rowEditing.flatMap { $0.rowID == identity ? $0 : nil } }
    private var expanded: Bool { editing?.isExpanded == true }
    private var hasMetadata: Bool {
        let current = editing?.savedTask ?? task
        return !current.project.isEmpty || current.plannedDate != nil || current.deadline != nil
    }
    private var attributesOverlap: CGFloat { hasMetadata ? max(0, headerHeight - titleHeight - 4) : 0 }
    private var phase: TaskCompletionFeedback.Phase? { store.completionFeedback.phase(for: task.id, context: store.completionContext) }
    private var checked: Bool { phase == .checked || phase == .covering || phase == .collapsing }
    private var visibility: CGFloat { phase == .covering || phase == .collapsing ? 0 : 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if task.canComplete {
                Button {
                    guard store.rowEditing == nil, !store.isSaving else { return }
                    Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) }
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .speed(3)))
                        .animation(reduceMotion ? nil : .default, value: checked)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .frame(height: headerHeight)
                .disabled(phase != nil)
                .allowsHitTesting(!store.isSaving && store.rowEditing == nil)
                .accessibilityRespondsToUserInteraction(store.rowEditing == nil)
                .accessibilityLabel("\(task.isOccurrence ? "Complete occurrence" : "Complete task"): \(task.description)")
                .accessibilityValue(checked ? "Completed" : phase == .saving ? "Saving" : "Not completed")
                .accessibilityIdentifier("complete-task-row-\(task.id.uuidString)")
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: hasMetadata ? 4 : 0) {
                    TextField("What needs to be done?", text: Binding(
                        get: { editing?.savedTask?.description ?? editing?.draft.taskDraft.description ?? task.description },
                        set: { editing?.draft.taskDraft.description = $0 }
                    ), axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .strikethrough(checked)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .disabled(!expanded || editing?.isSaving == true)
                    .lineLimit(1...max(1, min(5, Int(max(44, availableHeight - 100) / titleLineHeight))))
                    .frame(minHeight: hasMetadata ? 0 : 44, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { ($0.size.height * displayScale).rounded() / displayScale } action: { titleHeight = $0 }
                    .accessibilityIdentifier(expanded ? "task-description" : "task-row-title-" + task.id.uuidString)
                    .accessibilityHidden(!expanded)
                    if hasMetadata {
                        TaskListMetadata(task: editing?.savedTask ?? task, store: store)
                            .padding(.bottom, 2)
                            .modifier(TaskRowFade(editing: editing, disappearing: true))
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ($0.size.height * displayScale).rounded() / displayScale } action: { headerHeight = $0 }
                if let editing {
                    TaskRowEditor(store: store, editing: editing, titleFocused: $titleFocused,
                                  information: { rowActions.information(task) })
                        .environment(\.taskRowAvailableHeight, max(44, availableHeight - headerHeight - 24 + attributesOverlap))
                        .modifier(TaskRowAttributePosition(editing: editing, overlap: attributesOverlap))
                        .modifier(TaskRowFade(editing: editing))
                        .allowsHitTesting(expanded)
                        .accessibilityHidden(!expanded)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if !expanded {
                    Button {
                        if task.canEdit { expand() } else { edit(task) }
                    } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .disabled(phase != nil || editing != nil)
                        .accessibilityLabel { _ in
                            VStack {
                                Text(task.description)
                                TaskListMetadata(task: task, store: store)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier(identity)
                        .accessibilityHint(task.canEdit ? "Expand to edit title and attributes" : "Show task information")
                        .accessibilityAction(named: "Edit title and attributes", expand)
                }
            }
        }
        .modifier(TaskRowSpacing(editing: editing))
        .background {
            if expanded {
                Color.clear.taskKeyboardCommands(TaskEditorActions(save: rowActions.close).keyboardCommands + [
                    TaskKeyboardCommand(id: "collapse", input: "\u{1b}", modifiers: [], title: "Close Task Editor", action: rowActions.close)
                ])
                .allowsHitTesting(false)
            }
        }
        .onChange(of: editing?.isSaving) { _, saving in if saving == true { titleFocused = false } }
        .background(alignment: .top) {
            if editing != nil {
                RoundedRectangle(cornerRadius: 18).fill(.background)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
                    .modifier(TaskRowFade(editing: editing))
            }
        }
        .modifier(TaskRowDimming(editing: editing == nil ? store.rowEditing : nil))
        .allowsHitTesting(store.rowEditing == nil || editing != nil)
        .frame(maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds in
            rowGeometry.bounds = bounds
            editing?.measure(bounds)
        }
        .onChange(of: editing?.rowID) { _, _ in
            if let editing {
                editing.viewport = viewport
                editing.measure(rowGeometry.bounds)
                editing.focusInset = min(12, max(0, rowGeometry.bounds.minY - viewport.minY))
            }
        }
        .onChange(of: viewport) { _, bounds in editing?.viewport = bounds }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 6)
                Rectangle().fill(.white)
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom).frame(height: 6)
            }
            .padding(.horizontal, -12)
            .scaleEffect(x: 1, y: visibility)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: visibility)
        .accessibilityHidden(phase == .collapsing || store.rowEditing != nil && editing == nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(task.id)
        .contextMenu {
            if !expanded {
            TaskActivityButton(task: task, store: store).disabled(phase != nil)
            if task.canEdit { Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { expand() }.disabled(store.isSaving || phase != nil) }
            if task.canComplete {
                Button(task.isOccurrence ? "Complete occurrence" : "Complete", systemImage: "checkmark") { Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) } }.disabled(store.isSaving || phase != nil)
            }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !expanded { TaskActivityButton(task: task, store: store).tint(.orange).disabled(phase != nil) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.canEdit && !expanded {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { expand() }.disabled(store.isSaving || phase != nil)
            }
        }
    }
    private func expand() {
        store.expandRow(task, rowID: identity)
    }

}

@MainActor private final class TaskRowGeometry {
    var bounds = CGRect.zero
}

private struct TaskRowFocusOffset: ViewModifier {
    let editing: TaskRowEditing?

    func body(content: Content) -> some View {
        content.offset(y: -(editing.map { $0.focusInset * $0.revealProgress } ?? 0))
    }
}

private struct TaskRowDimming: ViewModifier {
    let editing: TaskRowEditing?

    func body(content: Content) -> some View {
        content.opacity(1 - 0.55 * (editing?.revealProgress ?? 0))
    }
}

private struct TaskRowSpacing: ViewModifier {
    let editing: TaskRowEditing?

    func body(content: Content) -> some View {
        let progress = editing?.revealProgress ?? 0
        content
            .padding(.top, 4 + (editing?.focusInset ?? 0) * progress)
            .padding(.bottom, 4 + 12 * progress)
    }
}

private struct TaskRowFade: ViewModifier {
    let editing: TaskRowEditing?
    var disappearing = false

    func body(content: Content) -> some View {
        let progress = editing?.revealProgress ?? 0
        if disappearing && progress == 1 {
            content.hidden()
        } else {
            content.opacity(disappearing ? 1 - progress : progress)
        }
    }
}

private struct TaskRowAttributePosition: ViewModifier {
    let editing: TaskRowEditing
    let overlap: CGFloat

    func body(content: Content) -> some View {
        content.padding(.top, -overlap * editing.revealProgress)
    }
}
