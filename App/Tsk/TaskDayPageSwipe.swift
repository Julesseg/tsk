import SwiftUI
import UIKit
import TskCore

@MainActor @Observable
final class TaskDayPaging {
    private let snapFeedback = UISelectionFeedbackGenerator()
    var offset: CGFloat = 0
    var isSettling = false
    var expanded = false
    static let pillHeight: CGFloat = 44
    var calendarPullDistance: CGFloat?
    var isCalendarVisible: Bool { expanded || (calendarPullDistance ?? 0) < 0 }
    var navigatorBounds = CGRect.zero
    var pages: [Date: [TaskRecord]] = [:]
    var calendars: [Date: TodayCalendarSnapshot] = [:]

    func settleCalendar(distance: CGFloat, velocity: CGFloat, reduceMotion: Bool, cancelled: Bool) {
        let projected = distance + velocity * 0.15
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) {
            if !cancelled, abs(projected) >= 75 { expanded = projected < 0 }
            calendarPullDistance = nil
        }
    }

    func settle(distance: CGFloat, velocity: CGFloat, width: CGFloat, store: TaskStore, reduceMotion: Bool, cancelled: Bool) {
        guard !isSettling else { return }
        let day = store.displayedDay
        let projected = distance + velocity * 0.15
        let move = !cancelled && abs(distance) > 20 && abs(projected) > max(60, width * 0.22)
        let direction = move ? (projected < 0 ? 1 : -1) : 0
        isSettling = true
        if move { snapFeedback.prepare() }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28), completionCriteria: .logicallyComplete) {
            offset = -CGFloat(direction) * width
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if direction != 0, store.isDayPage, store.displayedDay == day, !store.isSelectingTasks,
                   let target = Calendar.autoupdatingCurrent.date(byAdding: .day, value: direction, to: day) {
                    store.browseDay(target, cachedTasks: self.pages[target])
                    if store.displayedDay == target { self.snapFeedback.selectionChanged() }
                }
                self.offset = 0
                self.isSettling = false
            }
        }
    }
}

struct TaskDayPageSwipe: UIViewRepresentable {
    let store: TaskStore
    let paging: TaskDayPaging
    let viewport: CGRect
    let rows: [TaskSelectionRow]
    let reduceMotion: Bool

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ view: Anchor, context: Context) {
        view.pan.store = store
        view.pan.paging = paging
        view.pan.viewport = viewport
        view.pan.rows = rows
        view.pan.reduceMotion = reduceMotion
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) { view.pan.view?.removeGestureRecognizer(view.pan) }

    final class Anchor: UIView {
        let pan = DayPan()
        override func didMoveToWindow() {
            super.didMoveToWindow()
            pan.view?.removeGestureRecognizer(pan)
            window?.addGestureRecognizer(pan)
        }
    }

    final class DayPan: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
        weak var store: TaskStore?
        var paging: TaskDayPaging?
        var viewport = CGRect.zero
        var rows: [TaskSelectionRow] = []
        var reduceMotion = false
        private var origin = CGPoint.zero

        init() {
            super.init(target: nil, action: nil)
            delegate = self
            maximumNumberOfTouches = 1
            addTarget(self, action: #selector(swiped))
        }

        private var canPage: Bool {
            guard let store else { return false }
            return store.isDayPage && !store.isSelectingTasks && store.taskDrag == nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let store, let paging, !paging.isSettling, store.taskDrag == nil, !store.isSelectionPressActive,
                  !store.isSelectionGestureActive, store.rowEditing == nil, !store.isSaving,
                  store.presentedTaskPanels.isEmpty, !paging.isCalendarVisible, canPage else { return false }
            origin = touch.location(in: nil)
            guard !paging.navigatorBounds.contains(origin), viewport.contains(origin) else { return false }
            return !rows.contains { $0.bounds.contains(origin) }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let speed = velocity(in: nil)
            let point = location(in: nil)
            let movement = abs(speed.x) + abs(speed.y) > 1 ? speed : CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            return paging?.isCalendarVisible == false && canPage && abs(movement.x) > abs(movement.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer && !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer) && !(otherGestureRecognizer is DayPan)
        }

        @objc private func swiped() {
            guard let paging, let store else { return }
            let point = location(in: nil)
            let distance = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            let phase = state
            let speed = velocity(in: nil)
            let width = max(1, viewport.width)
            let reduceMotion = reduceMotion
            Task { @MainActor in
                switch phase {
                case .began, .changed:
                    paging.offset = min(width, max(-width, distance.x))
                case .ended, .cancelled, .failed:
                    paging.settle(distance: distance.x, velocity: speed.x, width: width, store: store, reduceMotion: reduceMotion, cancelled: phase != .ended)
                default: break
                }
            }
        }
    }
}

struct TaskDayPagingPages: ViewModifier {
    let store: TaskStore
    let calendar: TodayCalendarController
    let paging: TaskDayPaging
    private struct Neighbors: Equatable {
        let day: Date
        let tasks: [TaskRecord]
        let calendar: TodayCalendarSnapshot?
    }

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                content.offset(x: paging.offset)
                if paging.offset != 0 {
                    ForEach([-1, 1], id: \.self) { direction in
                        if let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: direction, to: store.displayedDay) {
                            preview(day: day)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .offset(x: CGFloat(direction) * geometry.size.width + paging.offset)
                        }
                    }
                }
            }
            .clipped()
        }
        .task(id: Neighbors(day: store.displayedDay, tasks: store.allTasks, calendar: calendar.snapshot)) { await loadNeighbors() }
    }

    private func loadNeighbors() async {
        let day = store.displayedDay
        var pages: [Date: [TaskRecord]] = [:]
        var calendars = paging.calendars.filter { $0.key == day }
        for direction in [-1, 1] {
            guard !Task.isCancelled, let date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: direction, to: day) else { return }
            if let value = try? await store.manager.dayPage(on: date) { pages[date] = value }
            calendars[date] = await store.manager.dayCalendar(on: date, from: calendar.source)
        }
        guard !Task.isCancelled, store.displayedDay == day else { return }
        paging.pages = pages
        paging.calendars = calendars
    }

    private func preview(day: Date) -> some View {
        let snapshot = paging.calendars[day]?.showing(calendar.preferences.visibility)
        let tasks = paging.pages[day] ?? []
        let rows = snapshot?.plannerRows(tasks: tasks) ?? tasks.map(DayPageItem.task)
        return VStack(spacing: 0) {
            TodayCalendarSection(snapshot: snapshot)
            List {
                Section {
                    if paging.pages[day] == nil { ProgressView() }
                    else if tasks.isEmpty { Text("Nothing planned for this day").foregroundStyle(.secondary) }
                    ForEach(rows) { item in
                        switch item {
                        case .task(let task): TaskListRow(task: task, store: store, edit: { _ in }, previewDay: day)
                        case .event(let value): TodayCalendarRow(value: value, timeZone: snapshot?.timeZone ?? .autoupdatingCurrent).padding(.vertical, 10)
                        }
                    }
                }
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .transformPreference(TaskSelectionRowsKey.self) { $0 = [:] }
        .transformPreference(TaskCalendarDragRowsKey.self) { $0 = [:] }
        .environment(\.taskSelectionScope, nil)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
