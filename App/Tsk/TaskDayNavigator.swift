import SwiftUI
import TskCore

struct TaskDayNavigator: View {
    let store: TaskStore
    let paging: TaskDayPaging
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var expanded: Bool { paging.expanded }
    @State private var month = Date()
    private var calendar: Calendar { .autoupdatingCurrent }
    private var canChooseDate: Bool { !store.isSelectionPressActive && !store.isSelectionGestureActive && store.rowEditing == nil && !store.isSaving }
    private var isScheduling: Bool { !store.selectedTaskIDs.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                monthCalendar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
            Button { setExpanded(!expanded) } label: {
                HStack(spacing: 7) {
                    Text(store.displayedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse date")
            .accessibilityValue(String(Int(store.displayedDay.timeIntervalSince1970)))
            .accessibilityHint(isScheduling ? "Tap to schedule selected tasks" : store.isSelectingTasks ? "Swipe up or tap to open the month calendar" : "Swipe left or right to change day. Swipe up or tap to open the month calendar")
            .accessibilityIdentifier("planner-date-pill")
        }
        .frame(width: expanded ? min(336, max(0, availableWidth - 32)) : nil)
        .contentShape(RoundedRectangle(cornerRadius: expanded ? 28 : 22))
        .highPriorityGesture(DragGesture(minimumDistance: 8).onEnded { value in
            let distance = value.translation
            guard canChooseDate, !paging.isSettling,
                  abs(distance.height) > 12, abs(distance.height) > abs(distance.width) * 1.5 else { return }
            setExpanded(distance.height < 0)
        })
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: expanded ? 28 : 22))
        .accessibilityElement(children: .contain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { paging.navigatorBounds = $0 }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onChange(of: store.completionContext) { _, _ in setExpanded(false) }
    }

    private func setExpanded(_ value: Bool) {
        if value { month = store.displayedDay }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) { paging.expanded = value }
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
        if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next }
    }
}

struct TaskPlannerLeadingDate: View {
    let task: TaskRecord
    let day: Date?
    let today: Date

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let scheduled = task.scheduled(calendar: calendar)
        let showsDate = scheduled.map { date in
            day.map { !calendar.isDate($0, inSameDayAs: date.date) } ?? true
        } ?? false
        let isCarried = task.status == "pending" && day == calendar.startOfDay(for: today)
            && scheduled.map { calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: today) } == true
        VStack(alignment: .trailing, spacing: 2) {
            if let scheduled, showsDate {
                Text(scheduled.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2)
            }
            if let scheduled, scheduled.hasTime {
                Text(scheduled.date, style: .time).font(.caption.monospacedDigit())
            } else if !showsDate {
                Text("-").font(.caption)
            }
        }
        .foregroundStyle(isCarried ? Color.red : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scheduled.map {
            "Scheduled " + $0.date.formatted(date: .abbreviated, time: $0.hasTime ? .shortened : .omitted)
        } ?? "Unscheduled")
        .accessibilityIdentifier("planner-leading-\(task.id.uuidString)")
    }
}
