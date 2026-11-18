import SwiftUI
import TskCore

struct TaskDayNavigator: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pull = Pull.idle
    @State private var browsedMonth: Date?
    @State private var labelWidth: CGFloat = 0
    @State private var calendarHeight: CGFloat = 0

    private enum Pull: Equatable {
        case idle, horizontal, vertical(CGFloat)

        var distance: CGFloat? {
            if case .vertical(let distance) = self { return distance }
            return nil
        }
    }

    private var expanded: Bool { paging.expanded }
    private var month: Date { browsedMonth ?? store.displayedDay }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var canChooseDate: Bool { !store.isSelectionPressActive && !store.isSelectionGestureActive && store.rowEditing == nil && !store.isSaving }
    private var isScheduling: Bool { !store.selectedTaskIDs.isEmpty }
    private var openWidth: CGFloat { min(336, max(0, availableWidth - 32)) }
    private var visibleHeight: CGFloat { min(calendarHeight, max(0, (expanded ? calendarHeight : 0) - (pull.distance ?? 0))) }
    private var openness: CGFloat { calendarHeight > 0 ? visibleHeight / calendarHeight : 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22 + 6 * openness) }
    private var settleAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.32) }

    var body: some View {
        VStack(spacing: 0) {
            monthCalendar
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(width: openWidth)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
                .frame(height: visibleHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(expanded && pull.distance == nil)
                .accessibilityHidden(!expanded)
            dateButton
        }
        .frame(width: labelWidth > 0 ? labelWidth + (openWidth - labelWidth) * openness : nil)
        .clipShape(shape)
        .contentShape(shape)
        .background {
            Color.clear.contentShape(shape).onTapGesture {}
        }
        .glassEffect(.regular, in: shape)
        .accessibilityElement(children: .contain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { paging.navigatorBounds = $0 }
        .animation(pull.distance == nil ? settleAnimation : nil, value: openness)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onChange(of: pull.distance != nil) { _, dragging in
            if dragging && !expanded { browsedMonth = store.displayedDay }
        }
        .onChange(of: pull.distance != nil && visibleHeight > 0) { _, visible in
            paging.isPullingCalendar = visible
        }
        .onChange(of: store.completionContext) { _, _ in setExpanded(false) }
        .onDisappear { paging.isPullingCalendar = false }
    }

    private var dateButton: some View {
        Button { setExpanded(!expanded) } label: {
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
            .frame(height: 44)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = min($0, openWidth) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse date")
        .accessibilityValue(String(Int(store.displayedDay.timeIntervalSince1970)))
        .accessibilityHint(expanded ? "Tap or swipe down to close the month calendar" : isScheduling ? "Tap to schedule selected tasks" : "Swipe up or tap to open the month calendar")
        .accessibilityIdentifier("planner-date-pill")
        .highPriorityGesture(calendarPull)
    }

    private var calendarPull: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($pull) { finger, pull, transaction in
                guard canChooseDate, !paging.isSettling else { return }
                let dy = finger.translation.height
                let dx = finger.translation.width
                switch pull {
                case .horizontal: return
                case .idle:
                    if abs(dx) > abs(dy) * 1.5 { pull = .horizontal; return }
                    guard abs(dy) > abs(dx) * 1.5 else { return }
                case .vertical: break
                }
                transaction.animation = nil
                pull = .vertical(dy)
            }
            .onEnded { finger in
                guard canChooseDate, !paging.isSettling, pull.distance != nil else { return }
                let projectedHeight = (expanded ? calendarHeight : 0) - finger.predictedEndTranslation.height
                setExpanded(projectedHeight >= calendarHeight / 2)
            }
    }

    private func setExpanded(_ value: Bool) {
        if value && !expanded && pull.distance == nil { browsedMonth = store.displayedDay }
        withAnimation(settleAnimation) { paging.expanded = value }
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
                        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("planner-date-\(Int(date.timeIntervalSince1970))")
                    } else {
                        Color.clear.frame(height: 40).accessibilityHidden(true)
                    }
                }
            }
            if store.isSaving { ProgressView("Saving selected tasks") }
            if !calendar.isDate(store.displayedDay, inSameDayAs: store.currentDate) {
                Button("Today") {
                    chooseDate(store.currentDate)
                }
                .frame(height: 36)
                .accessibilityIdentifier("planner-return-today")
            }
        }
        .disabled(!canChooseDate)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner-month-calendar")
    }

    private func chooseDate(_ date: Date) {
        guard canChooseDate else { return }
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
            && scheduled.map { calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: today) } == true
        VStack(spacing: 1) {
            if let scheduled, showsDate {
                Text(scheduled.date, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: dateSize))
            }
            if let scheduled, scheduled.hasTime {
                Text(scheduled.date, style: .time).font(.caption.bold().monospacedDigit())
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
