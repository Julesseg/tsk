import SwiftUI
import QuartzCore
import TskCore

@MainActor @Observable
final class TaskDayPaging {
    struct Preview: Equatable {
        let day: Date
        let side: CGFloat
    }

    struct Snap {
        let start: CFTimeInterval
        let from: CGFloat
        let to: CGFloat
        static let duration = 0.16

        func position(at time: CFTimeInterval) -> CGFloat {
            let remaining = 1 - min(1, max(0, (time - start) / Self.duration))
            return to + (from - to) * remaining * remaining * remaining
        }
    }

    private(set) var preview: Preview?
    private(set) var trailingPreview: Preview?
    private(set) var snap: Snap?
    private(set) var offset: CGFloat = 0
    @ObservationIgnored private var dragOrigin: CGFloat?
    typealias Animate = (_ move: () -> Void, _ finished: @escaping () -> Void) -> Void
    private let animateSnap: Animate
    @ObservationIgnored private var sourceDay: Date?

    var expanded = false
    static let pillHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 8
    static var collapsedNavigatorHeight: CGFloat { pillHeight + 2 * verticalPadding }
    var calendarPullDistance: CGFloat?
    var isCalendarVisible: Bool { expanded || (calendarPullDistance ?? 0) < 0 }
    @ObservationIgnored var navigatorBounds = CGRect.zero
    var pages: [Date: [TaskRecord]] = [:]
    var calendars: [Date: TodayCalendarSnapshot] = [:]

    init(animateSnap: @escaping Animate = { move, finished in
        withAnimation(.timingCurve(1.0 / 3, 1, 2.0 / 3, 1, duration: Snap.duration),
                      completionCriteria: .removed, move, completion: finished)
    }) {
        self.animateSnap = animateSnap
    }

    func settleCalendar(distance: CGFloat, velocity: CGFloat, reduceMotion: Bool, cancelled: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            let projected = distance + velocity * 0.15
            if !cancelled, abs(projected) >= 75 { expanded = projected < 0 }
            calendarPullDistance = nil
        }
    }

    func drag(distance: CGFloat, width: CGFloat, store: TaskStore) {
        if dragOrigin == nil {
            interrupt(in: store)
            dragOrigin = offset
        }
        offset = min(1, max(-1, (dragOrigin ?? 0) + distance / max(1, width)))
        guard offset != 0 else { return }
        let side: CGFloat = offset < 0 ? 1 : -1
        if preview?.side != side,
           let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: Int(side), to: store.displayedDay) {
            trailingPreview = nil
            preview = Preview(day: day, side: side)
        }
    }

    func settle(distance: CGFloat, velocity: CGFloat, width: CGFloat, store: TaskStore, reduceMotion: Bool, cancelled: Bool) {
        if dragOrigin == nil { drag(distance: distance, width: width, store: store) }
        let threshold = max(60, width * 0.22)
        let travel = abs(distance) > threshold ? distance : distance + velocity * 0.15
        if !cancelled, abs(distance) > 20, abs(travel) > threshold,
           let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: travel < 0 ? 1 : -1, to: store.displayedDay) {
            navigate(to: day, store: store, reduceMotion: reduceMotion)
        } else {
            animate(to: 0, store: store, reduceMotion: reduceMotion)
        }
    }

    func navigate(to day: Date, store: TaskStore, reduceMotion: Bool) {
        interrupt(in: store)
        let target = Calendar.autoupdatingCurrent.startOfDay(for: day)
        guard target != store.displayedDay else { reset(); return }
        let side: CGFloat = target > store.displayedDay ? 1 : -1
        if let preview, preview.day != target, offset * preview.side < 0 {
            if preview.side == side { offset = 0 }
            else { trailingPreview = preview }
        }
        preview = Preview(day: target, side: side)
        animate(to: -side, store: store, reduceMotion: reduceMotion)
    }

    func cancelDrag(store: TaskStore, reduceMotion: Bool) {
        if dragOrigin != nil { animate(to: 0, store: store, reduceMotion: reduceMotion) }
    }

    private func animate(to target: CGFloat, store: TaskStore, reduceMotion: Bool) {
        dragOrigin = nil
        sourceDay = store.displayedDay
        let motion = Snap(start: CACurrentMediaTime(), from: offset, to: target)
        snap = motion
        if reduceMotion || offset == target { finish(in: store); return }
        animateSnap({ self.offset = target }) { [weak self, weak store] in
            guard let self, let store, self.snap?.start == motion.start else { return }
            self.finish(in: store)
        }
    }

    private func interrupt(in store: TaskStore) {
        guard let snap else { return }
        guard sourceDay == store.displayedDay else { reset(); return }
        let position = snap.position(at: CACurrentMediaTime())
        let oldDay = store.displayedDay
        let destination = preview
        finish(in: store)
        if let destination, oldDay != store.displayedDay {
            offset = min(1, max(-1, position + destination.side))
            preview = Preview(day: oldDay, side: -destination.side)
        } else {
            offset = position
            preview = destination
        }
    }

    private func finish(in store: TaskStore) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let snap, snap.to != 0, sourceDay == store.displayedDay, store.isDayPage, let preview {
                if store.awaitingDaySnapshot != store.displayedDay { pages[store.displayedDay] = store.tasks }
                store.browseDay(preview.day, cachedTasks: pages[preview.day])
            }
            reset()
        }
    }

    func reset() {
        sourceDay = nil
        dragOrigin = nil
        snap = nil
        offset = 0
        preview = nil
        trailingPreview = nil
    }
}
