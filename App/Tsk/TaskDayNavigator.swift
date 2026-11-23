import SwiftUI
import TskCore

struct TaskDayNavigator: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    var openPlannerDay: ((Date) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calendarHeight: CGFloat = 0
    @State private var retainingCalendar = false
    @State private var monthGrid = TaskDayMonthGrid.Cache()

    private var expanded: Bool { paging.expanded }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var canChooseDate: Bool { !store.isSelectionPressActive && !store.isSelectionGestureActive && store.rowEditing == nil && !store.isSaving }
    private var canPage: Bool { store.isDayPage && !store.isSelectingTasks && store.taskDrag == nil && !expanded }
    private var today: Date { calendar.startOfDay(for: store.currentDate) }
    private var canReturnToToday: Bool {
        canChooseDate && !store.isSelectingTasks && store.taskDrag == nil && (!store.isDayPage || store.displayedDay != today)
    }
    private var isScheduling: Bool { !store.selectedTaskIDs.isEmpty }
    private var openWidth: CGFloat { min(336, max(0, availableWidth - 32)) }
    private var visibleHeight: CGFloat { min(calendarHeight, max(0, (expanded ? calendarHeight : 0) - (paging.calendarPullDistance ?? 0))) }
    private var openness: CGFloat { calendarHeight > 0 ? visibleHeight / calendarHeight : 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22 + 14 * openness) }
    private var settleAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }

    var body: some View {
        TaskDayPillWidth(expandedWidth: openWidth, openness: openness) {
            dateLabel.accessibilityHidden(true)
        }
        .padding(.top, visibleHeight)
        .overlay(alignment: .top) {
            if paging.isCalendarVisible || retainingCalendar {
                TaskDayMonthCalendar(store: store, grid: monthGrid, width: max(0, openWidth - 24),
                                     canChooseDate: canChooseDate, expanded: expanded, choose: chooseDate)
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
            TaskDayPillInput(day: store.isDayPage ? store.displayedDay : nil, hint: pillHint, canReturnToToday: canReturnToToday,
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
        Group {
            if store.isDayPage {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left").font(.caption2.weight(.semibold))
                    dayLabel
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 16)
            } else {
                Text("-").frame(minWidth: TaskDayPaging.pillHeight)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .frame(height: TaskDayPaging.pillHeight)
    }

    private var dayLabel: some View {
        dayText(store.displayedDay)
            .hidden()
            .overlay {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    dayText(store.displayedDay)
                        .frame(width: width, height: geometry.size.height)
                        .overlay {
                            ForEach([paging.trailingPreview, paging.preview].compactMap { $0 }, id: \.day) { preview in
                                dayText(preview.day)
                                    .frame(width: width, height: geometry.size.height)
                                    .offset(x: width * preview.side)
                                    .transition(.identity)
                            }
                        }
                        .offset(x: width * paging.offset)
                }
            }
            .clipped()
    }

    private func dayText(_ day: Date) -> some View {
        Text(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .monospacedDigit()
            .minimumScaleFactor(0.8)
    }

    private var pillHint: String {
        if expanded { return "Tap or swipe down to close the month calendar" }
        if isScheduling { return "Tap to schedule selected tasks" }
        let browse = store.isDayPage ? "Swipe left or right to browse days. " : ""
        let hold = canReturnToToday ? " Hold to go to Today." : ""
        return browse + "Swipe up or tap to open the month calendar." + hold
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
        setExpanded(false)
        navigate(to: today)
    }

    private func chooseDate(_ date: Date) {
        guard canChooseDate else { return }
        if store.isSelectingTasks {
            guard date >= today else { return }
            Task {
                if await store.scheduleSelection(on: date) { setExpanded(false) }
            }
        } else {
            setExpanded(false)
            navigate(to: date)
        }
    }

    private func navigate(to day: Date) {
        if store.isDayPage {
            paging.navigate(to: day, store: store, reduceMotion: reduceMotion)
        } else if let openPlannerDay {
            openPlannerDay(day)
        } else {
            store.browseDay(day)
        }
    }
}

private struct TaskDayPillInput: UIViewRepresentable {
    let day: Date?
    let hint: String
    let canReturnToToday: Bool
    let activate: () -> Void
    let returnToToday: () -> Void
    let pan: (Axis, CGPoint, CGPoint, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> Input { Input() }

    func updateUIView(_ input: Input, context: Context) {
        input.actions = self
        input.hold.isEnabled = canReturnToToday
        input.accessibilityValue = day.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        input.accessibilityHint = hint
        input.accessibilityCustomActions = canReturnToToday ? [input.todayAction] : nil
    }

    final class Pan: UIPanGestureRecognizer {
        private var touchOrigin = CGPoint.zero
        var didEnd: ((CGPoint, CGPoint) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if numberOfTouches == 0, let touch = touches.first {
                touchOrigin = touch.location(in: view?.window)
            }
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            let point = touches.first?.location(in: view?.window)
            super.touchesEnded(touches, with: event)
            // UIKit can coalesce the target callbacks for a fast swipe.
            if state == .ended, let point {
                didEnd?(distance(to: point), velocity(in: view?.window))
            }
        }

        func distance(to point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - touchOrigin.x, y: point.y - touchOrigin.y)
        }
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
            let pan = Pan(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            pan.didEnd = { [weak self] distance, velocity in self?.pan(distance: distance, velocity: velocity, state: .ended) }
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

        @objc private func panned(_ recognizer: Pan) {
            guard recognizer.state != .ended else { return }
            pan(distance: recognizer.distance(to: recognizer.location(in: window)), velocity: recognizer.velocity(in: window), state: recognizer.state)
        }

        private func pan(distance: CGPoint, velocity: CGPoint, state: UIGestureRecognizer.State) {
            if axis == nil {
                let direction = distance == .zero ? velocity : distance
                axis = abs(direction.y) > abs(direction.x) ? .vertical : .horizontal
            }
            if let axis { actions?.pan(axis, distance, velocity, state) }
            if state == .ended || state == .cancelled { axis = nil }
        }
    }
}

private struct TaskDayMonthCalendar: View {
    let store: TaskStore
    let grid: TaskDayMonthGrid.Cache
    let width: CGFloat
    let canChooseDate: Bool
    let expanded: Bool
    let choose: (Date) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var browsedMonth: Date?
    @State private var offset: CGFloat = 0
    @State private var settling: UUID?

    private var calendar: Calendar { .autoupdatingCurrent }
    private var month: Date { browsedMonth ?? calendar.dateInterval(of: .month, for: store.displayedDay)?.start ?? store.displayedDay }

    var body: some View {
        let activeMonth = month
        let previous = calendar.date(byAdding: .month, value: -1, to: activeMonth)
        let next = calendar.date(byAdding: .month, value: 1, to: activeMonth)
        let months = [previous, activeMonth, next].compactMap { $0 }
        let pages = Array(zip(months, grid.views(for: months)))
        let isScheduling = store.isSelectingTasks
        VStack(spacing: 4) {
            if isScheduling {
                Text("Schedule \(store.selectedTaskIDs.count) selected").font(.subheadline.weight(.semibold))
            }
            TaskMonthPages(activeIndex: previous == nil ? 0 : 1, offset: offset) {
                ForEach(pages, id: \.0) { date, view in
                    let active = date == activeMonth
                    let side: CGFloat = active ? 0 : date < activeMonth ? -1 : 1
                    VStack(spacing: 4) {
                        Text(date, format: .dateTime.month(.wide).year()).font(.headline)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .padding(.horizontal, 44)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .mask {
                                Rectangle().frame(width: max(0, width - 88))
                                    .offset(x: -width * (side + offset))
                            }
                        TaskDayMonthGrid(grid: view, month: date, selected: store.displayedDay,
                                         minimum: isScheduling ? calendar.startOfDay(for: store.currentDate) : nil,
                                         expanded: expanded && active, choose: choose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(active && settling == nil)
                    .accessibilityHidden(!active)
                    .transition(.identity)
                }
            }
            .clipped()
            .overlay(alignment: .top) {
                HStack {
                    Button("Previous month", systemImage: "chevron.left") { settle(-1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    Spacer()
                    Button("Next month", systemImage: "chevron.right") { settle(1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .disabled(settling != nil)
            }
            if store.isSaving { ProgressView("Saving selected tasks") }
        }
        .contentShape(Rectangle())
        .gesture(TaskMonthSwipe(enabled: expanded && canChooseDate, update: pan))
        .disabled(!canChooseDate)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(expanded ? "planner-month-calendar" : "")
        .onChange(of: expanded) { _, open in
            if !open {
                withAnimation(nil) {
                    settling = nil
                    offset = 0
                    browsedMonth = nil
                }
            }
        }
    }

    private func pan(distance: CGFloat, velocity: CGFloat, phase: UIGestureRecognizer.State) {
        guard settling == nil else { return }
        switch phase {
        case .began, .changed:
            offset = min(1, max(-1, distance / max(1, width)))
        case .ended:
            let threshold = max(42, width * 0.24)
            let travel = abs(distance) >= threshold ? distance : distance + velocity * 0.12
            settle(abs(distance) >= 20 && abs(travel) >= threshold ? (travel < 0 ? 1 : -1) : 0)
        case .cancelled, .failed:
            settle(0)
        default: break
        }
    }

    private func settle(_ step: Int) {
        guard settling == nil else { return }
        let destination = calendar.date(byAdding: .month, value: step, to: month) ?? month
        let target = destination == month ? 0 : -CGFloat(step)
        let id = UUID()
        settling = id
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22), completionCriteria: .removed) {
            offset = target
        } completion: {
            guard settling == id else { return }
            withAnimation(nil) {
                browsedMonth = destination
                offset = 0
                settling = nil
            }
        }
    }
}

private struct TaskMonthPages: Layout {
    let activeIndex: Int
    var offset: CGFloat

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let height = subviews[activeIndex].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + (CGFloat(index - activeIndex) + offset) * bounds.width
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

private struct TaskMonthSwipe: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let update: (CGFloat, CGFloat, UIGestureRecognizer.State) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Direction { Direction() }

    func makeUIGestureRecognizer(context: Context) -> TaskDayPillInput.Pan {
        let pan = TaskDayPillInput.Pan()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ pan: TaskDayPillInput.Pan, context: Context) {
        pan.isEnabled = enabled
        pan.didEnd = { distance, velocity in update(distance.x, velocity.x, .ended) }
    }

    func handleUIGestureRecognizerAction(_ pan: TaskDayPillInput.Pan, context: Context) {
        guard pan.state != .ended else { return }
        let distance = pan.distance(to: pan.location(in: pan.view?.window))
        update(distance.x, pan.velocity(in: pan.view?.window).x, pan.state)
    }

    final class Direction: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? TaskDayPillInput.Pan else { return false }
            let distance = pan.distance(to: pan.location(in: pan.view?.window))
            return abs(distance.x) > abs(distance.y) * 1.5
        }
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
