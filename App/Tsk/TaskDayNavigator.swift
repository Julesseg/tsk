import SwiftUI
import TskCore

struct TaskDayNavigator: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calendarHeight: CGFloat = 0
    @State private var retainingCalendar = false
    @State private var monthGrid = TaskDayMonthGrid.Cache()

    private var expanded: Bool { paging.expanded }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var canChooseDate: Bool { !store.isSelectionPressActive && !store.isSelectionGestureActive && store.rowEditing == nil && !store.isSaving }
    private var canPage: Bool { store.isDayPage && !store.isSelectingTasks && store.taskDrag == nil && !expanded }
    private var today: Date { calendar.startOfDay(for: store.currentDate) }
    private var canReturnToToday: Bool { canChooseDate && canPage && store.displayedDay != today }
    private var isScheduling: Bool { !store.selectedTaskIDs.isEmpty }
    private var openWidth: CGFloat { min(336, max(0, availableWidth - 32)) }
    private var visibleHeight: CGFloat { min(calendarHeight, max(0, (expanded ? calendarHeight : 0) - (paging.calendarPullDistance ?? 0))) }
    private var openness: CGFloat { calendarHeight > 0 ? visibleHeight / calendarHeight : 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22 + 6 * openness) }
    private var settleAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }

    var body: some View {
        TaskDayPillWidth(expandedWidth: openWidth, openness: openness) {
            dateLabel.accessibilityHidden(true)
        }
        .padding(.top, visibleHeight)
        .overlay(alignment: .top) {
            if paging.isCalendarVisible || retainingCalendar {
                TaskDayMonthCalendar(store: store, paging: paging, grid: monthGrid, canChooseDate: canChooseDate, expanded: expanded)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(width: openWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
                    .frame(height: visibleHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(expanded && paging.calendarPullDistance == nil)
                    .accessibilityHidden(!expanded)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .background {
            Color.clear.contentShape(shape).onTapGesture {}
        }
        .glassEffect(.regular, in: shape)
        .overlay(alignment: .bottom) {
            TaskDayPillInput(day: store.displayedDay, hint: pillHint, canReturnToToday: canReturnToToday,
                             activate: { if canChooseDate { setExpanded(!expanded) } },
                             returnToToday: returnToToday, pan: pan)
                .frame(height: TaskDayPaging.pillHeight)
        }
        .accessibilityElement(children: .contain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { paging.navigatorBounds = $0 }
        .animation(paging.calendarPullDistance == nil ? settleAnimation : nil, value: openness)
        .padding(.horizontal, 16)
        .padding(.vertical, TaskDayPaging.verticalPadding)
        .frame(maxWidth: .infinity)
        .task(id: paging.isCalendarVisible) {
            if paging.isCalendarVisible { retainingCalendar = true }
            else if retainingCalendar {
                if !reduceMotion {
                    do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                }
                retainingCalendar = false
            }
        }
        .onChange(of: store.completionContext) { _, _ in setExpanded(false) }
        .onDisappear { paging.calendarPullDistance = nil }
    }

    private var dateLabel: some View {
        HStack(spacing: 7) {
            Text(store.displayedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .monospacedDigit()
            Image(systemName: "chevron.up")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(180 * openness))
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: TaskDayPaging.pillHeight)
    }

    private var pillHint: String {
        if expanded { return "Tap or swipe down to close the month calendar" }
        if isScheduling { return "Tap to schedule selected tasks" }
        return canReturnToToday ? "Swipe up to open the calendar. Hold to go to Today." : "Swipe up or tap to open the month calendar"
    }

    private func pan(axis: Axis, distance: CGPoint, velocity: CGPoint, state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed:
            guard canChooseDate else { return }
            if axis == .vertical { paging.calendarPullDistance = distance.y }
            else if canPage { paging.drag(distance: distance.x, width: availableWidth, store: store) }
        case .ended, .cancelled:
            let cancelled = state == .cancelled || !canChooseDate
            if axis == .vertical {
                paging.settleCalendar(distance: distance.y, velocity: velocity.y, reduceMotion: reduceMotion, cancelled: cancelled)
            } else if canPage && !cancelled {
                paging.settle(distance: distance.x, velocity: velocity.x, width: availableWidth, store: store, reduceMotion: reduceMotion, cancelled: false)
            } else { paging.cancelDrag(store: store, reduceMotion: reduceMotion) }
        default: break
        }
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        withAnimation(settleAnimation) { paging.expanded = value }
    }

    private func returnToToday() {
        paging.navigate(to: today, store: store, reduceMotion: reduceMotion)
    }
}

private struct TaskDayPillInput: UIViewRepresentable {
    let day: Date
    let hint: String
    let canReturnToToday: Bool
    let activate: () -> Void
    let returnToToday: () -> Void
    let pan: (Axis, CGPoint, CGPoint, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> Input { Input() }

    func updateUIView(_ input: Input, context: Context) {
        input.actions = self
        input.hold.isEnabled = canReturnToToday
        input.accessibilityValue = String(Int(day.timeIntervalSince1970))
        input.accessibilityHint = hint
        input.accessibilityCustomActions = canReturnToToday ? [input.todayAction] : nil
    }

    final class Input: UIView {
        var actions: TaskDayPillInput?
        private var axis: Axis?
        let hold = UILongPressGestureRecognizer()
        lazy var todayAction = UIAccessibilityCustomAction(name: "Go to Today") { [weak self] _ in
            guard let actions = self?.actions, actions.canReturnToToday else { return false }
            actions.returnToToday()
            return true
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "planner-date-pill"
            accessibilityLabel = "Browse date"
            accessibilityTraits = .button
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            hold.addTarget(self, action: #selector(held))
            hold.allowableMovement = 8
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: pan)
            tap.require(toFail: hold)
            for recognizer in [pan, hold, tap] { addGestureRecognizer(recognizer) }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func accessibilityActivate() -> Bool { tapped(); return true }
        @objc private func tapped() { actions?.activate() }
        @objc private func held() { if hold.state == .began { actions?.returnToToday() } }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            let distance = recognizer.translation(in: window)
            let velocity = recognizer.velocity(in: window)
            if axis == nil {
                let direction = distance == .zero ? velocity : distance
                axis = abs(direction.y) > abs(direction.x) ? .vertical : .horizontal
            }
            if let axis { actions?.pan(axis, distance, velocity, recognizer.state) }
            if recognizer.state == .ended || recognizer.state == .cancelled { axis = nil }
        }
    }
}

private struct TaskDayMonthCalendar: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let grid: TaskDayMonthGrid.Cache
    let canChooseDate: Bool
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var browsedMonth: Date?

    private var calendar: Calendar { .autoupdatingCurrent }
    private var month: Date { browsedMonth ?? store.displayedDay }

    var body: some View {
        let displayedDay = store.displayedDay
        let isScheduling = store.isSelectingTasks
        let today = calendar.startOfDay(for: store.currentDate)
        VStack(spacing: 4) {
            if isScheduling {
                Text("Schedule \(store.selectedTaskIDs.count) selected").font(.subheadline.weight(.semibold))
            }
            HStack {
                Button("Previous month", systemImage: "chevron.left") { moveMonth(-1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { moveMonth(1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            TaskDayMonthGrid(grid: grid, month: month, selected: displayedDay, minimum: isScheduling ? today : nil,
                             expanded: expanded, choose: chooseDate)
                .fixedSize(horizontal: false, vertical: true)
            if store.isSaving { ProgressView("Saving selected tasks") }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { swipe in
            let dx = swipe.translation.width
            guard canChooseDate, abs(dx) >= 42, abs(dx) > abs(swipe.translation.height) * 1.5 else { return }
            moveMonth(dx < 0 ? 1 : -1)
        })
        .disabled(!canChooseDate)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(expanded ? "planner-month-calendar" : "")
        .onChange(of: expanded) { _, open in
            if !open { browsedMonth = nil }
        }
    }

    private func chooseDate(_ date: Date) {
        guard canChooseDate else { return }
        if store.isSelectingTasks {
            guard date >= calendar.startOfDay(for: store.currentDate) else { return }
            Task {
                if await store.scheduleSelection(on: date) { close() }
            }
        } else {
            close()
            paging.navigate(to: date, store: store, reduceMotion: reduceMotion)
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { paging.expanded = false }
    }

    private func moveMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: month) { browsedMonth = next }
    }
}

private struct TaskDayPillWidth: Layout {
    let expandedWidth: CGFloat
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func makeCache(subviews: Subviews) -> CGSize { subviews[0].sizeThatFits(.unspecified) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache label: inout CGSize) -> CGSize {
        let closed = min(label.width, expandedWidth)
        let progress = min(1, max(0, openness))
        return CGSize(width: closed + (expandedWidth - closed) * progress, height: label.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) {
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

struct TaskPlannerLeadingDate: View {
    let task: TaskRecord
    let day: Date?
    let today: Date

    @ScaledMetric(relativeTo: .caption2) private var dateSize: CGFloat = 9

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let scheduled = task.scheduled(calendar: calendar)
        let showsDate = scheduled.map { date in
            day.map { !calendar.isDate($0, inSameDayAs: date.date) } ?? true
        } ?? false
        let isCarried = task.status == "pending" && day == calendar.startOfDay(for: today)
            && scheduled.map { $0.hasTime && $0.date < calendar.startOfDay(for: today) } == true
        VStack(spacing: 1) {
            if let scheduled, showsDate {
                Text(scheduled.date, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: dateSize))
            }
            if let scheduled, scheduled.hasTime {
                Text(scheduled.date, style: .time)
                    .font(.caption.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else if !showsDate {
                Text("-").font(.caption.bold())
            }
        }
        .foregroundStyle(isCarried ? Color.red : Color.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scheduled.map {
            "Scheduled " + $0.date.formatted(date: .abbreviated, time: $0.hasTime ? .shortened : .omitted)
        } ?? "Unscheduled")
        .accessibilityIdentifier("planner-leading-\(task.id.uuidString)")
    }
}
