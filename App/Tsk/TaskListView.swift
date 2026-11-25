import SwiftUI
import UIKit
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let calendar: TodayCalendarController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gestureRows = TaskListGestureRows()
    @State private var calendars = TaskSelectionCalendars()
    @State private var selectionScope = TaskSelectionScope()
    @State private var keyboardFrame = CGRect.null
    @State private var isVisible = false
    @State private var selectionBarHeight: CGFloat = 0
    @State var dayPaging = TaskDayPaging()
    var workspaceControls: TaskWorkspaceControls? = nil
    var openPlannerDay: ((Date) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
        let keyboardInset = keyboardOverlap(in: geometry.frame(in: .global))
        let isPickerClosed = store.selectionDateField == nil
        let showsNavigator = store.isDayPage || store.isSelectingTasks || workspaceControls != nil
        let footerHeight = (showsNavigator ? TaskDayPaging.collapsedNavigatorHeight : 0) + (store.isSelectingTasks ? selectionBarHeight : 0)
        let viewport = geometry.frame(in: .global)
        let rowViewport = viewport.divided(atDistance: footerHeight + keyboardInset, from: .maxYEdge).remainder
        let extendsBehindHomeIndicator = store.isDayPage && store.rowEditing == nil
        Group {
            if store.isDayPage {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        List {
                            TodayCalendarSection(snapshot: dayCalendarSnapshot, hours: calendar.preferences.hours, acceptsTaskDrops: true)
                            Section {
                                CalendarFixtureControls(calendar: calendar)
                                captureRow
                                if let error = store.error, store.visibleTasks.isEmpty, store.captureTask == nil { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                                else if store.awaitingDaySnapshot != store.displayedDay && store.visibleTasks.isEmpty && store.captureTask == nil {
                                    TaskDayEmptyRow().taskDayRowInsets()
                                }
                                ForEach(store.visibleTasks) { task in
                                    TaskListRow(task: task, store: store).id(task.id)
                                }
                            }
                            .listSectionSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .accessibilityIdentifier("task-list")
                        #if DEBUG
                        .accessibilityValue(store.taskDragProof)
                        #endif
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
                            TaskListRow(task: task, store: store)
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    #if DEBUG
                    .accessibilityValue(store.taskDragProof)
                    #endif
                    .refreshable { await store.reload() }
                    .task(id: store.rowEditing?.rowID) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: store.rowEditing?.isAnimating) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                    .task(id: geometry.size.height - keyboardInset) { await Task.yield(); revealEditor(using: proxy, viewport: geometry.frame(in: .global), keyboardInset: keyboardInset) }
                }
            }
        }
        .background {
            TaskListGestures(store: store, scope: selectionScope, rows: gestureRows, paging: dayPaging,
                             viewport: geometry.frame(in: .global), isVisible: isVisible, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
        }
        .scrollDisabled(store.isSelectionGestureActive)
        .contentMargins(.bottom, footerHeight + (extendsBehindHomeIndicator ? geometry.safeAreaInsets.bottom : 0), for: .scrollContent)
        .onPreferenceChange(TaskSelectionRowsKey.self) { gestureRows.tasks = Array($0.values) }
        .onPreferenceChange(TaskCalendarDropTargetsKey.self) { gestureRows.events = $0 }
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
                    TaskSelectionBar(store: store, calendars: calendars)
                        .onGeometryChange(for: CGFloat?.self) { geometry in
                            isPickerClosed ? geometry.size.height : nil
                        } action: { height in
                            if let height { selectionBarHeight = height }
                        }
                        .transition(.opacity)
                }
                if showsNavigator {
                    TaskWorkspaceFooter(store: store, paging: dayPaging, availableWidth: geometry.size.width,
                                        controls: workspaceControls, openPlannerDay: openPlannerDay)
                }
            }
            .frame(width: geometry.size.width)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: store.selectionDateField)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.isSelectingTasks)
        }
        .onChange(of: store.completionContext) { _, _ in store.endTaskSelection() }
        .modifier(TaskRowFocusOffset(editing: store.rowEditing))
        .transaction { if store.rowEditing != nil { $0.animation = nil } }
        .safeAreaPadding(.bottom, store.rowEditing == nil ? 0 : keyboardInset)
        .environment(\.taskRowAvailableHeight, max(120, geometry.size.height - keyboardInset - 24))
        .environment(\.taskRowViewport, rowViewport)
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
        .overlay { if !store.isDayPage && store.isLoading && store.visibleTasks.isEmpty { ProgressView() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardFrame = .null }
    }

    private var dayCalendarSnapshot: TodayCalendarSnapshot? {
        if let value = calendar.snapshot, value.day?.start == store.displayedDay { return value }
        return dayPaging.calendars[store.displayedDay]?.showing(calendar.preferences.visibility)
    }

    @ViewBuilder private var captureRow: some View {
        if let task = store.captureTask {
            TaskListRow(task: task, store: store, rowIdentifier: store.rowEditing?.rowID)
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

struct TaskDayEmptyRow: View {
    var body: some View {
        Text("Nothing planned for this day")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func taskDayRowInsets() -> some View {
        listRowInsets(.horizontal, 20)
    }
}

@MainActor @Observable private final class TaskListGestureRows {
    var tasks: [TaskSelectionRow] = []
    var events: [TaskCalendarDropTarget] = []
}

private struct TaskListGestures: View {
    let store: TaskStore
    let scope: TaskSelectionScope
    let rows: TaskListGestureRows
    let paging: TaskDayPaging
    let viewport: CGRect
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        TaskNativeDrag(store: store, scope: scope, rows: rows.tasks, eventTargets: rows.events, reduceMotion: reduceMotion)
        TaskSelectionGesture(store: store, scope: scope, viewport: viewport, rows: rows.tasks)
        if (store.isDayPage || store.isSelectingTasks) && isVisible {
            TaskDayPageSwipe(store: store, paging: paging, viewport: viewport, rows: rows.tasks, reduceMotion: reduceMotion)
        }
    }
}

struct TaskListRow: View {
    let task: TaskRecord
    let store: TaskStore
    var rowIdentifier: String?
    var previewDay: Date?
    var body: some View {
        TaskListRowContent(task: task, store: store, rowIdentifier: rowIdentifier,
                           previewDay: previewDay, selected: store.selectedTaskIDs.contains(task.id))
    }
}

private struct TaskListRowContent: View {
    let task: TaskRecord
    let store: TaskStore
    let rowIdentifier: String?
    let previewDay: Date?
    let selected: Bool
    private var isPreview: Bool { previewDay != nil }
    private var day: Date? { previewDay ?? (store.isDayPage ? store.displayedDay : nil) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @FocusState private var titleFocused: Bool
    @FocusState private var focusedNote: UTF8String?
    @State private var headerHeight: CGFloat = 32
    @State private var titleHeight: CGFloat = 28
    @State private var projectBadgeHeight: CGFloat = 0
    @State private var rowGeometry = TaskRowGeometry()
    @ScaledMetric(relativeTo: .subheadline) private var titleLineHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var metadataSize: CGFloat = 10
    @Environment(\.taskRowAvailableHeight) private var availableHeight
    @Environment(\.taskRowViewport) private var viewport
    private var identity: String { rowIdentifier ?? "task-" + task.id.uuidString }
    private var editing: TaskRowEditing? { isPreview ? nil : store.rowEditing.flatMap { $0.rowID == identity ? $0 : nil } }
    private var expanded: Bool { editing?.isExpanded == true }
    private var displayedTask: TaskRecord { editing?.savedTask ?? task }
    private var hasProject: Bool { !displayedTask.project.isEmpty }
    private var phase: TaskCompletionFeedback.Phase? { isPreview ? nil : store.completionFeedback.phase(for: task.id, context: store.completionContext) }
    private var checked: Bool { displayedTask.status == "completed" || phase == .checked || phase == .covering || phase == .collapsing }
    private var visibility: CGFloat { phase == .covering || phase == .collapsing ? 0 : 1 }

    private var planningTask: TaskRecord {
        guard let editing, editing.savedTask == nil else { return displayedTask }
        return TaskRecord(id: task.id, attributes: editing.draft.taskDraft.attributes)
    }

    private func activateRowControl() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        titleFocused = false
        focusedNote = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let editing {
                TaskRowEditor(store: store, editing: editing, titleFocused: $titleFocused, focusedNote: $focusedNote,
                              onActivate: activateRowControl)
                    .environment(\.taskRowAvailableHeight, max(44, availableHeight - headerHeight - 32))
                    .padding(.top, 8 * editing.revealProgress)
                    .modifier(TaskRowFade(editing: editing))
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
            }
        }
        .background {
            if !isPreview {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear.preference(key: TaskSelectionRowsKey.self,
                        value: [identity: TaskSelectionRow(id: task.id, rowID: identity,
                            bounds: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: editing == nil ? frame.height : min(headerHeight, frame.height))),
                            isEditing: editing != nil)])
                        .background { TaskSelectionRowAnchor().allowsHitTesting(false) }
                }
            }
        }
        .padding(.horizontal, 12)
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
        .onGeometryChange(for: CGRect.self) { [isPreview] geometry in
            isPreview ? .zero : geometry.frame(in: .global)
        } action: { bounds in
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
        .listRowInsets(EdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 9))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(task.id)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.canEdit && !expanded && !store.isSelectingTasks {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { expand() }.disabled(store.isSaving || phase != nil)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            if let editing {
                TaskRowPickerButton(editing: editing, parameter: .scheduled, onActivate: activateRowControl) {
                    scheduledLabel.frame(width: TaskSelectionRow.slotWidth, height: headerHeight)
                }
            } else {
                scheduledLabel
                    .frame(width: TaskSelectionRow.slotWidth, height: headerHeight)
                    .contentShape(Rectangle())
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
                        .frame(minWidth: TaskSelectionRow.completionControlWidth, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .frame(height: headerHeight)
                .disabled(phase != nil)
                .allowsHitTesting(!store.isSaving && store.rowEditing == nil)
                .accessibilityRespondsToUserInteraction(store.rowEditing == nil)
                .accessibilityLabel(store.isSelectingTasks ? "\(selected ? "Deselect task" : "Select task"): \(task.description)" : "\(task.isOccurrence ? "Complete occurrence" : "Complete task"): \(task.description)")
                .accessibilityValue(store.isSelectingTasks ? (selected ? "Selected" : "Not selected") : checked ? "Completed" : phase == .saving ? "Saving" : "Not completed")
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
            } else {
                Color.clear.frame(width: TaskSelectionRow.completionControlWidth, height: headerHeight)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Group {
                        if let editing {
                            TextField("What needs to be done?", text: Binding(
                                get: { editing.savedTask?.description ?? editing.draft.taskDraft.description },
                                set: { editing.draft.taskDraft.description = $0 }
                            ), axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .disabled(!expanded || editing.isSaving || !task.canEdit)
                        } else {
                            Text(verbatim: task.description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .ignore)
                        }
                    }
                    .font(.subheadline.leading(.tight))
                    .foregroundStyle(checked ? .secondary : .primary)
                    .strikethrough(checked)
                    .lineLimit(1...max(1, min(5, Int(max(44, availableHeight - 100) / titleLineHeight))))
                    .onGeometryChange(for: CGFloat.self) { [displayScale] in ($0.size.height * displayScale).rounded() / displayScale } action: { titleHeight = $0 }
                    .accessibilityLabel("Task title")
                    .accessibilityIdentifier(expanded ? "task-description" : "task-row-title-" + task.id.uuidString)
                    .accessibilityAction(named: "Select") { store.toggleSelection(task.id) }
                    .accessibilityHidden(!expanded)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    deadline
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { [displayScale] in ($0.size.height * displayScale).rounded() / displayScale } action: { headerHeight = $0 }
                if hasProject {
                    let progress = editing?.revealProgress ?? 0
                    Text(displayedTask.project)
                        .font(.system(size: metadataSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.11), in: Capsule())
                        .padding(.top, 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { projectBadgeHeight = $0 }
                        .frame(height: editing == nil ? nil : projectBadgeHeight * (1 - progress), alignment: .top)
                        .clipped()
                        .opacity(1 - progress)
                        .padding(.top, -max(0, (headerHeight - titleHeight) / 2) * (1 - progress))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if !expanded && !isPreview {
                    Button {
                        if store.isSelectingTasks { store.toggleSelection(task.id) }
                        else { expand() }
                    } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(TaskRowTapButtonStyle())
                        .disabled(phase != nil || editing != nil)
                        .accessibilityLabel { _ in
                            VStack {
                                Text(task.description)
                                if !task.project.isEmpty { Text(task.project) }
                                TaskPlanningCaption(task: task, today: store.currentDate)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier(identity)
                        .accessibilityHint(store.isSelectingTasks ? "Toggle selection" : task.canComplete ? (store.taskDragContext != nil ? "Tap to edit; drag the title to reorder; touch the scheduled time to select" : "Tap to edit title and attributes; touch the scheduled time to select") : task.canEdit ? "Expand to edit title and attributes" : "Expand task")
                        .accessibilityAction(named: task.canEdit ? "Edit title and attributes" : "Expand task", expand)
                        .accessibilityAction(named: "Select") { store.toggleSelection(task.id) }
                }
            }
        }
    }

    private var scheduledLabel: some View {
        TaskPlannerLeadingDate(task: planningTask, day: day, today: store.currentDate)
    }

    @ViewBuilder private var deadline: some View {
        if let editing {
            TaskRowPickerButton(editing: editing, parameter: .deadline, onActivate: activateRowControl) {
                deadlineLabel.frame(maxHeight: .infinity, alignment: .trailing)
            }
            .layoutPriority(1)
        } else if displayedTask.deadline != nil {
            deadlineLabel.layoutPriority(1).accessibilityHidden(true)
        }
    }

    private var deadlineLabel: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            TaskPlanningCaption(task: planningTask, today: store.currentDate, showsEmptyFlag: editing != nil)
        }
    }

    private var completedCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.body)
            .foregroundStyle(Color.secondary)
            .frame(minWidth: TaskSelectionRow.completionControlWidth, minHeight: headerHeight)
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
