import SwiftUI
import TskCore

struct TaskDayNavigator: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var touchingPill = false
    @State private var dragAxis: Axis?
    @State private var todayPress: Task<Void, Never>?
    @State private var didReturnToToday = false
    @State private var browsedMonth: Date?
    @State private var calendarHeight: CGFloat = 0

    private var expanded: Bool { paging.expanded }
    private var month: Date { browsedMonth ?? store.displayedDay }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var canChooseDate: Bool { !store.isSelectionPressActive && !store.isSelectionGestureActive && store.rowEditing == nil && !store.isSaving }
    private var canPage: Bool { store.isDayPage && !store.isSelectingTasks && store.taskDrag == nil && !expanded }
    private var today: Date { calendar.startOfDay(for: store.currentDate) }
    private var canReturnToToday: Bool { canChooseDate && canPage && !paging.isSettling && store.displayedDay != today }
    private var isScheduling: Bool { !store.selectedTaskIDs.isEmpty }
    private var openWidth: CGFloat { min(336, max(0, availableWidth - 32)) }
    private var visibleHeight: CGFloat { min(calendarHeight, max(0, (expanded ? calendarHeight : 0) - (paging.calendarPullDistance ?? 0))) }
    private var openness: CGFloat { calendarHeight > 0 ? visibleHeight / calendarHeight : 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22 + 6 * openness) }
    private var settleAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.32) }

    var body: some View {
        TaskDayPillWidth(expandedWidth: openWidth, openness: openness) {
            dateButton
        }
        .padding(.top, visibleHeight)
        .overlay(alignment: .top) {
            if paging.isCalendarVisible {
                monthCalendar
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
        .accessibilityElement(children: .contain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { paging.navigatorBounds = $0 }
        .animation(paging.calendarPullDistance == nil ? settleAnimation : nil, value: openness)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onChange(of: paging.isCalendarVisible) { _, visible in
            if visible { browsedMonth = store.displayedDay }
        }
        .onChange(of: store.completionContext) { _, _ in setExpanded(false) }
        .onChange(of: touchingPill) { _, touching in
            if !touching {
                Task { @MainActor in
                    guard !touchingPill else { return }
                    finishDrag(distance: .zero, velocity: .zero, cancelled: true)
                }
            }
        }
        .onDisappear {
            todayPress?.cancel()
            paging.calendarPullDistance = nil
        }
    }

    private var dateButton: some View {
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
        .contentShape(Rectangle())
        .gesture(pillDrag)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setExpanded(!expanded) }
        .accessibilityActions {
            if canReturnToToday { Button("Go to Today", action: returnToToday) }
        }
        .accessibilityLabel("Browse date")
        .accessibilityValue(String(Int(store.displayedDay.timeIntervalSince1970)))
        .accessibilityHint(expanded ? "Tap or swipe down to close the month calendar" : isScheduling ? "Tap to schedule selected tasks" : canReturnToToday ? "Swipe up to open the calendar. Hold to go to Today." : "Swipe up or tap to open the month calendar")
        .accessibilityIdentifier("planner-date-pill")
    }

    private var pillDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($touchingPill) { _, touching, _ in touching = true }
            .onChanged { finger in
                guard canChooseDate, !paging.isSettling, !didReturnToToday else { return }
                let x = finger.translation.width
                let y = finger.translation.height
                if dragAxis == nil, max(abs(x), abs(y)) > 8 {
                    todayPress?.cancel()
                    todayPress = nil
                    dragAxis = abs(y) > abs(x) ? .vertical : .horizontal
                }
                if dragAxis == nil, canReturnToToday, todayPress == nil {
                    todayPress = Task {
                        do { try await Task.sleep(for: .milliseconds(500)) }
                        catch { return }
                        guard canReturnToToday, touchingPill, dragAxis == nil else { return }
                        didReturnToToday = true
                        returnToToday()
                    }
                }
                switch dragAxis {
                case .vertical: paging.calendarPullDistance = y
                case .horizontal where canPage: paging.offset = min(availableWidth, max(-availableWidth, x))
                default: break
                }
            }
            .onEnded { finger in
                finishDrag(distance: finger.translation, velocity: finger.velocity, cancelled: !canChooseDate || paging.isSettling)
            }
    }

    private func finishDrag(distance: CGSize, velocity: CGSize, cancelled: Bool) {
        todayPress?.cancel()
        todayPress = nil
        let axis = dragAxis
        dragAxis = nil
        if didReturnToToday {
            didReturnToToday = false
            return
        }
        switch axis {
        case .vertical:
            paging.settleCalendar(distance: distance.height, velocity: velocity.height, reduceMotion: reduceMotion, cancelled: cancelled)
        case .horizontal where canPage || paging.offset != 0:
            paging.settle(distance: distance.width, velocity: velocity.width, width: availableWidth, store: store,
                          reduceMotion: reduceMotion, cancelled: cancelled || !canPage)
        case nil where !cancelled && max(abs(distance.width), abs(distance.height)) <= 8:
            setExpanded(!expanded)
        default: break
        }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(settleAnimation) { paging.expanded = value }
    }

    private func returnToToday() {
        store.browseDay(today, cachedTasks: paging.pages[today])
    }

    private var monthCalendar: some View {
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.caption).foregroundStyle(.secondary).frame(height: 24)
                        .accessibilityHidden(true)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let selected = calendar.isDate(date, inSameDayAs: store.displayedDay)
                        Button {
                            chooseDate(date)
                        } label: {
                            Text(date, format: .dateTime.day())
                                .font(.body.weight(selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isScheduling && date < today)
                        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("planner-date-\(Int(date.timeIntervalSince1970))")
                    } else {
                        Color.clear.frame(height: 40).accessibilityHidden(true)
                    }
                }
            }
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
        .accessibilityIdentifier("planner-month-calendar")
    }

    private func chooseDate(_ date: Date) {
        guard canChooseDate, !isScheduling || date >= today else { return }
        if isScheduling {
            Task {
                guard await store.scheduleSelection(on: date) else { return }
                setExpanded(false)
            }
        } else {
            store.browseDay(date)
            setExpanded(false)
        }
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let padding = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + range.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let label = subviews[0].sizeThatFits(.unspecified)
        let closed = min(label.width, expandedWidth)
        let progress = min(1, max(0, openness))
        return CGSize(width: closed + (expandedWidth - closed) * progress, height: label.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
