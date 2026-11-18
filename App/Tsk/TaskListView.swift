import SwiftUI
import UIKit
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let calendar: TodayCalendarController
    let edit: (TaskRecord) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionRows: [String: TaskSelectionRow] = [:]
    @State private var eventRows: [CalendarEventIdentity: TaskCalendarDragRow] = [:]
    @State private var selectionScope = TaskSelectionScope()
    @State private var keyboardFrame = CGRect.null
    @State private var isVisible = false
    @State private var footerHeight: CGFloat = 0
    @State var dayPaging = TaskDayPaging()

    var body: some View {
        GeometryReader { geometry in
        let keyboardInset = keyboardOverlap(in: geometry.frame(in: .global))
        let extendsBehindHomeIndicator = store.isDayPage && store.rowEditing == nil
        Group {
            if store.isDayPage {
                VStack(spacing: 0) {
                    TodayCalendarSection(snapshot: dayCalendarSnapshot)
                    ScrollViewReader { proxy in
                        List {
                            Section {
                                CalendarFixtureControls(calendar: calendar)
                                captureRow
                                if let error = store.error, store.visibleTasks.isEmpty, store.captureTask == nil { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                                else if store.visibleTasks.isEmpty && store.captureTask == nil { Text("Nothing planned for this day").foregroundStyle(.secondary) }
                                ForEach(dayRows) { item in
                                    switch item {
                                    case .task(let task): TaskListRow(task: task, store: store, edit: edit).id(task.id)
                                    case .event(let value):
                                        TodayCalendarRow(value: value, timeZone: dayCalendarSnapshot?.timeZone ?? .autoupdatingCurrent)
                                            .padding(.vertical, 10)
                                            .background {
                                                GeometryReader { row in
                                                    Color.clear.preference(key: TaskCalendarDragRowsKey.self, value: [value.id: TaskCalendarDragRow(event: value.event, bounds: row.frame(in: .global))])
                                                }
                                            }
                                    }
                                }
                            }
                            .listSectionSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }.accessibilityIdentifier("task-list")
                            .refreshable { await store.reload(); await calendar.refresh() }
                            .task(id: store.rowEditing?.rowID) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                            .task(id: store.rowEditing?.isAnimating) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                            .task(id: geometry.size.height - keyboardInset) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    }
                }
                .modifier(TaskDayPagingPages(store: store, calendar: calendar, paging: dayPaging))
                .ignoresSafeArea(.container, edges: extendsBehindHomeIndicator ? .bottom : [])
            } else if let error = store.error, store.visibleTasks.isEmpty, store.captureTask == nil {
                ContentUnavailableView {
                    Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await store.reload() } }
                }
            } else if store.visibleTasks.isEmpty && store.captureTask == nil {
                ContentUnavailableView(emptyTitle, systemImage: "checklist", description: Text("Capture a task to get started. Saved tasks stay on this device when you're offline."))
            } else {
                ScrollViewReader { proxy in
                    List {
                        captureRow
                        ForEach(store.visibleTasks) { task in
                            TaskListRow(task: task, store: store, edit: edit)
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    .refreshable { await store.reload() }
                    .task(id: store.rowEditing?.rowID) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: store.rowEditing?.isAnimating) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: geometry.size.height - keyboardInset) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                }
            }
        }
        .background {
            TaskNativeDrag(store: store, scope: selectionScope, rows: Array(selectionRows.values), eventRows: Array(eventRows.values), reduceMotion: reduceMotion)
                .allowsHitTesting(false)
            TaskSelectionGesture(store: store, scope: selectionScope, viewport: geometry.frame(in: .global), rows: selectionRows)
                .allowsHitTesting(false)
            if (store.isDayPage || store.isSelectingTasks) && isVisible {
                TaskDayPageSwipe(store: store, paging: dayPaging, viewport: geometry.frame(in: .global), rows: Array(selectionRows.values), reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
            }
        }
        #if DEBUG
        .accessibilityValue(store.taskDragProof)
        #endif
        .contentMargins(.bottom, footerHeight + (extendsBehindHomeIndicator ? geometry.safeAreaInsets.bottom : 0), for: .scrollContent)
        .onPreferenceChange(TaskSelectionRowsKey.self) { selectionRows = $0 }
        .onPreferenceChange(TaskCalendarDragRowsKey.self) { eventRows = $0 }
        .scrollDisabled(store.isSelectionGestureActive)
        .overlay(alignment: .top) {
            if store.selectionDateField != nil {
                Button { store.selectionDateField = nil } label: {
                    Color.clear
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close date picker")
                .accessibilityIdentifier("dismiss-selection-date")
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if store.isSelectingTasks {
                    TaskSelectionBar(store: store).transition(.opacity)
                }
                if store.isDayPage || store.isSelectingTasks { TaskDayNavigator(store: store, paging: dayPaging, availableWidth: geometry.size.width) }
            }
            .frame(width: geometry.size.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.isSelectingTasks)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: store.selectionDateField)
        .onChange(of: store.completionContext) { _, _ in store.endTaskSelection() }
        .modifier(TaskRowFocusOffset(editing: store.rowEditing))
        .transaction { if store.rowEditing != nil { $0.animation = nil } }
        .safeAreaPadding(.bottom, store.rowEditing == nil ? 0 : keyboardInset)
        .environment(\.taskRowAvailableHeight, max(120, geometry.size.height - keyboardInset - 24))
        .environment(\.taskRowViewport, geometry.frame(in: .global))
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .environment(\.taskSelectionScope, selectionScope)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.completionFeedback.removingIDs(context: store.completionContext))
        .environment(\.defaultMinListRowHeight, 0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .overlay { if store.isLoading && store.visibleTasks.isEmpty { ProgressView() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardFrame = .null }
    }

    private var dayCalendarSnapshot: TodayCalendarSnapshot? {
        if let value = calendar.snapshot, value.day?.start == store.displayedDay { return value }
        return dayPaging.calendars[store.displayedDay]?.showing(calendar.preferences.visibility)
    }

    private var dayRows: [DayPageItem] {
        dayCalendarSnapshot?.plannerRows(tasks: store.visibleTasks) ?? store.visibleTasks.map(DayPageItem.task)
    }

    @ViewBuilder private var captureRow: some View {
        if let task = store.captureTask {
            TaskListRow(task: task, store: store, edit: edit, rowIdentifier: store.rowEditing?.rowID)
                .id(task.id)
        }
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
        guard !Task.isCancelled, let editing = store.rowEditing else { return }
        if editing.isCapture, editing.bounds == .zero {
            proxy.scrollTo(editing.draft.original.id, anchor: .top)
            return
        }
        guard editorIsClipped(in: viewport, keyboardInset: keyboardInset) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            proxy.scrollTo(editing.draft.original.id, anchor: .top)
        }
    }

    private var emptyTitle: String {
        switch store.query {
        case .today: return "Nothing planned or due today"
        case .completed: return "No completed tasks"
        default: return "No unfinished tasks"
        }
    }
}

struct TaskListRow: View {
    let task: TaskRecord
    let store: TaskStore
    let edit: (TaskRecord) -> Void
    var rowIdentifier: String?
    var previewDay: Date?
    private var isPreview: Bool { previewDay != nil }
    private var day: Date? { previewDay ?? (store.isDayPage ? store.displayedDay : nil) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @FocusState private var titleFocused: Bool
    @State private var headerHeight: CGFloat = 32
    @State private var titleHeight: CGFloat = 28
    @State private var titleContentHeight: CGFloat = 28
    @State private var rowGeometry = TaskRowGeometry()
    @ScaledMetric(relativeTo: .subheadline) private var titleLineHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var metadataSize: CGFloat = 10
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @Environment(\.taskRowViewport) private var viewport
    @Environment(\.taskRowActions) private var rowActions
    private var identity: String { rowIdentifier ?? "task-" + task.id.uuidString }
    private var editing: TaskRowEditing? { isPreview ? nil : store.rowEditing.flatMap { $0.rowID == identity ? $0 : nil } }
    private var expanded: Bool { editing?.isExpanded == true }
    private var displayedTask: TaskRecord { editing?.savedTask ?? task }
    private var hasProject: Bool { !displayedTask.project.isEmpty }
    private var titleBottom: CGFloat { max(0, (headerHeight - titleContentHeight) / 2) + titleHeight }
    private var attributesOverlap: CGFloat { hasProject ? max(0, headerHeight - titleBottom - 4) : 0 }
    private var phase: TaskCompletionFeedback.Phase? { store.completionFeedback.phase(for: task.id, context: store.completionContext) }
    private var checked: Bool { displayedTask.status == "completed" || phase == .checked || phase == .covering || phase == .collapsing }
    private var selected: Bool { store.selectedTaskIDs.contains(task.id) }
    private var visibility: CGFloat { phase == .covering || phase == .collapsing ? 0 : 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if editing?.isCapture != true {
                TaskPlannerLeadingDate(task: displayedTask, day: day, today: store.currentDate)
                    .frame(width: TaskSelectionRow.slotWidth, height: headerHeight)
                    .contentShape(Rectangle())
                    .modifier(TaskRowFade(editing: editing, disappearing: true))
                    .accessibilityAddTraits(task.canComplete ? .isButton : [])
                    .accessibilityHint(task.canComplete ? (selected ? "Deselect task" : "Select task") : "")
                    .accessibilityAction { if task.canComplete { store.toggleSelection(task.id) } }
            }
            if task.canComplete {
                Button {
                    if store.isSelectingTasks { store.toggleSelection(task.id); return }
                    guard store.rowEditing == nil, !store.isSaving else { return }
                    Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) }
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.body).foregroundStyle(Color.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .speed(3)))
                        .animation(reduceMotion ? nil : .default, value: checked)
                        .frame(minWidth: 44, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .frame(height: headerHeight)
                .disabled(phase != nil)
                .allowsHitTesting(!store.isSaving && store.rowEditing == nil)
                .accessibilityRespondsToUserInteraction(store.rowEditing == nil)
                .accessibilityLabel(store.isSelectingTasks ? "\(store.selectedTaskIDs.contains(task.id) ? "Deselect task" : "Select task"): \(task.description)" : "\(task.isOccurrence ? "Complete occurrence" : "Complete task"): \(task.description)")
                .accessibilityValue(store.isSelectingTasks ? (store.selectedTaskIDs.contains(task.id) ? "Selected" : "Not selected") : checked ? "Completed" : phase == .saving ? "Saving" : "Not completed")
                .accessibilityIdentifier("complete-task-row-\(task.id.uuidString)")
                .accessibilityHidden(editing?.isCapture == true)
            }
            else if displayedTask.status == "completed" {
                if task.canReopen {
                    Button {
                        Task { _ = await store.reopen(id: task.id) }
                    } label: {
                        completedCheckmark
                    }
                    .buttonStyle(.borderless)
                    .disabled(phase != nil || store.rowEditing != nil || store.isSaving || store.isSelectingTasks)
                    .accessibilityLabel("Reopen task: \(task.description)")
                    .accessibilityValue("Completed")
                    .accessibilityIdentifier("completed-task-row-\(task.id.uuidString)")
                } else {
                    completedCheckmark
                        .accessibilityLabel("Completed task: \(task.description)")
                        .accessibilityValue("Completed")
                        .accessibilityIdentifier("completed-task-row-\(task.id.uuidString)")
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("What needs to be done?", text: Binding(
                            get: { editing?.savedTask?.description ?? editing?.draft.taskDraft.description ?? task.description },
                            set: { editing?.draft.taskDraft.description = $0 }
                        ), axis: .vertical)
                        .font(.subheadline.leading(.tight))
                        .foregroundStyle(checked ? .secondary : .primary)
                        .strikethrough(checked)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .disabled(!expanded || editing?.isSaving == true || !task.canEdit)
                        .lineLimit(1...max(1, min(5, Int(max(44, availableHeight - 100) / titleLineHeight))))
                        .onGeometryChange(for: CGFloat.self) { ($0.size.height * displayScale).rounded() / displayScale } action: { titleHeight = $0 }
                        .accessibilityLabel("Task title")
                        .accessibilityIdentifier(expanded ? "task-description" : "task-row-title-" + task.id.uuidString)
                        .accessibilityAction(named: "Select") { store.toggleSelection(task.id) }
                        .accessibilityHidden(!expanded)
                        if hasProject {
                            Text(displayedTask.project)
                                .font(.system(size: metadataSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.11), in: Capsule())
                                .padding(.top, 1)
                                .modifier(TaskRowFade(editing: editing, disappearing: true))
                                .accessibilityHidden(true)
                        }
                        if store.isDayPage {
                            TaskAvailabilityView(task: displayedTask, store: store)
                                .accessibilityHidden(true)
                                .modifier(TaskRowFade(editing: editing, disappearing: true))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { [displayScale] in ($0.size.height * displayScale).rounded() / displayScale } action: { titleContentHeight = $0 }
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    if displayedTask.deadline != nil {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            TaskPlanningCaption(task: displayedTask, today: store.currentDate)
                                .multilineTextAlignment(.trailing)
                        }
                        .layoutPriority(1)
                        .frame(maxHeight: .infinity, alignment: .trailing)
                        .modifier(TaskRowFade(editing: editing, disappearing: true))
                        .accessibilityHidden(true)
                    }
                }
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
                        if store.isSelectingTasks { store.toggleSelection(task.id) }
                        else if task.canEdit { expand() } else { edit(task) }
                    } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(TaskRowTapButtonStyle())
                        .disabled(phase != nil || editing != nil)
                        .accessibilityLabel { _ in
                            VStack {
                                Text(task.description)
                                if !task.project.isEmpty { Text(task.project) }
                                if store.isDayPage { TaskAvailabilityView(task: task, store: store) }
                                TaskPlanningCaption(task: task, today: store.currentDate)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier(identity)
                        .accessibilityHint(store.isSelectingTasks ? "Toggle selection" : task.canComplete ? (store.taskDragContext != nil ? "Tap to edit; drag the title to reorder; touch the scheduled time to select" : "Tap to edit title and attributes; touch the scheduled time to select") : task.canEdit ? "Expand to edit title and attributes" : "Show task information")
                        .accessibilityAction(named: "Edit title and attributes", expand)
                        .accessibilityAction(named: "Select") { store.toggleSelection(task.id) }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .global)
                Color.clear.preference(key: TaskSelectionRowsKey.self,
                    value: [identity: TaskSelectionRow(id: task.id, rowID: identity,
                        bounds: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: min(headerHeight, frame.height))),
                        isEditing: editing != nil)])
                    .background { TaskSelectionRowAnchor().allowsHitTesting(false) }
            }
        }
        .modifier(TaskRowSpacing(editing: editing))
        .modifier(TaskSelectionRowFeedback(selected: selected))
        .opacity((checked ? 0.55 : 1) * (store.isTaskDragLifted && store.taskDrag?.ids.contains(task.id) == true ? 0 : 1))
        .onChange(of: expanded) { _, expanded in
            if !expanded { titleFocused = false }
            else if editing?.isCapture == true { titleFocused = true }
        }
        .onAppear {
            if let editing {
                editing.viewport = viewport
                editing.measure(rowGeometry.bounds)
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
            Rectangle().padding(.horizontal, -12).scaleEffect(x: 1, y: visibility)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: visibility)
        .accessibilityHidden(phase == .collapsing || store.rowEditing != nil && editing == nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(task.id)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.canEdit && !expanded && !store.isSelectingTasks {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { expand() }.disabled(store.isSaving || phase != nil)
            }
        }
    }
    private var completedCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.body)
            .foregroundStyle(Color.secondary)
            .frame(minWidth: 44, minHeight: headerHeight)
            .contentShape(Rectangle())
    }

    private func expand() {
        store.expandRow(task, rowID: identity)
    }

}

@MainActor private final class TaskRowGeometry {
    var bounds = CGRect.zero
}

private struct TaskRowTapButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.taskSelectionScope) private var scope

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                TaskRowTapTarget(scope: scope, isEnabled: isEnabled, action: configuration.trigger)
            }
            .accessibilityAction {
                if isEnabled { configuration.trigger() }
            }
    }
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
            .padding(.top, 2 + (editing?.focusInset ?? 0) * progress)
            .padding(.bottom, 2 + 12 * progress)
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
