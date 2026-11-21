import SwiftUI
import UIKit
import TskCore

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
            guard let store, let paging, store.taskDrag == nil, !store.isSelectionPressActive,
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
            switch phase {
            case .began, .changed:
                paging.drag(distance: distance.x, width: width, store: store)
            case .ended:
                paging.settle(distance: distance.x, velocity: speed.x, width: width, store: store, reduceMotion: reduceMotion, cancelled: false)
            case .cancelled, .failed:
                paging.cancelDrag(store: store, reduceMotion: reduceMotion)
            default: break
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
        let neighbors = Neighbors(day: store.displayedDay, tasks: store.allTasks, calendar: calendar.snapshot)
        GeometryReader { geometry in
            content
                .overlay {
                    ForEach([paging.trailingPreview, paging.preview].compactMap { $0 }, id: \.day) { preview in
                        TaskDayPreview(day: preview.day, store: store, paging: paging, calendar: calendar)
                            .offset(x: preview.side * geometry.size.width)
                            .transition(.identity)
                    }
                }
                .modifier(DayPageTranslation(paging: paging, width: geometry.size.width))
                .clipped()
        }
        .task(id: neighbors) { await loadNeighbors(neighbors) }
        .sensoryFeedback(.selection, trigger: store.displayedDay)
        .onDisappear { paging.reset() }
    }

    private func loadNeighbors(_ neighbors: Neighbors) async {
        let day = neighbors.day
        var pages = paging.pages.filter { $0.key == day }
        var calendars = paging.calendars.filter { $0.key == day }
        for direction in [-1, 1] {
            guard !Task.isCancelled, let date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: direction, to: day) else { return }
            pages[date] = await store.manager.dayPage(on: date, in: neighbors.tasks)
            calendars[date] = await store.manager.dayCalendar(on: date, from: calendar.source)
        }
        guard !Task.isCancelled, store.displayedDay == day else { return }
        if let target = paging.preview?.day, let warm = paging.pages[target], pages[target] == nil { pages[target] = warm }
        paging.pages = pages
        paging.calendars = calendars
    }
}

private struct DayPageTranslation: ViewModifier {
    let paging: TaskDayPaging
    let width: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: width * paging.offset)
    }
}

private struct TaskDayPreview: View {
    let day: Date
    let store: TaskStore
    let paging: TaskDayPaging
    let calendar: TodayCalendarController

    var body: some View {
        let snapshot = paging.calendars[day]?.showing(calendar.preferences.visibility)
        let tasks = paging.pages[day] ?? []
        return VStack(spacing: 0) {
            List {
                TodayCalendarSection(snapshot: snapshot, hours: calendar.preferences.hours)
                Section {
                    if paging.pages[day] != nil && tasks.isEmpty { Text("Nothing planned for this day").foregroundStyle(.secondary) }
                    ForEach(tasks) { task in
                        TaskListRow(task: task, store: store, edit: { _ in }, previewDay: day)
                    }
                }
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .task(id: day) {
            guard paging.pages[day] == nil else { return }
            let tasks = await store.manager.dayPage(on: day, in: store.allTasks)
            guard !Task.isCancelled else { return }
            paging.pages[day] = tasks
        }
        .transformPreference(TaskSelectionRowsKey.self) { $0 = [:] }
        .environment(\.taskSelectionScope, nil)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
