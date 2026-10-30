import SwiftUI
import UIKit
import TskCore
import TskNative

struct TaskSelectionRow: Equatable {
    let id: UUID
    let rowID: String
    let bounds: CGRect
    let isEditing: Bool
}

struct TaskSelectionRowsKey: PreferenceKey {
    static let defaultValue: [String: TaskSelectionRow] = [:]
    static func reduce(value: inout [String: TaskSelectionRow], nextValue: () -> [String: TaskSelectionRow]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TaskSelectionGesture: UIViewRepresentable {
    let store: TaskStore
    let viewport: CGRect
    let rows: [String: TaskSelectionRow]

    func makeUIView(context: Context) -> SelectionAnchor {
        let view = SelectionAnchor()
        view.recognizer.store = store
        return view
    }

    func updateUIView(_ view: SelectionAnchor, context: Context) {
        view.recognizer.viewport = viewport
        view.recognizer.updateRows(Array(rows.values))
    }

    static func dismantleUIView(_ view: SelectionAnchor, coordinator: ()) { view.detach() }
}

final class SelectionAnchor: UIView {
    let recognizer = TaskSelectionRecognizer()
    override func didMoveToWindow() {
        super.didMoveToWindow()
        Task { @MainActor [weak self] in
            guard let self, self.recognizer.view !== self.window else { return }
            self.recognizer.finish()
            self.recognizer.view?.removeGestureRecognizer(self.recognizer)
            self.window?.addGestureRecognizer(self.recognizer)
        }
    }
    func detach() {
        recognizer.finish()
        recognizer.view?.removeGestureRecognizer(recognizer)
    }
}

final class TaskSelectionRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var store: TaskStore?
    var viewport = CGRect.zero
    var rows: [TaskSelectionRow] = []
    private var initial = CGPoint.zero
    private var latest = CGPoint.zero
    private var traversedY: ClosedRange<CGFloat> = 0...0
    private var previousY: CGFloat = 0
    private var frozenRows: [TaskSelectionRow] = []
    private var touched: Set<UUID> = []
    private var scrollViews: [(UIScrollView, Bool, CGPoint)] = []
    #if DEBUG
    private var proof = TaskSelectionGestureProof()
    #endif
    private var preparation: Task<Void, Never>?
    private var collapsedLayout: CheckedContinuation<Void, Never>?
    private var generation = 0
    private var released = false
    private var horizontal = false
    private var crossedThreshold = false
    private var tracking = false

    init() {
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, let store, !store.isSaving else { state = .failed; return }
        generation += 1
        preparation?.cancel()
        collapsedLayout?.resume()
        collapsedLayout = nil
        initial = touch.location(in: nil)
        latest = initial
        traversedY = initial.y...initial.y
        guard viewport.contains(initial), let row = rows.first(where: { $0.bounds.contains(initial) }),
              store.visibleTasks.contains(where: { $0.id == row.id && $0.canComplete }) else { state = .failed; return }
        touched = [row.id]
        frozenRows = rows
        previousY = initial.y
        released = false
        horizontal = false
        crossedThreshold = false
        tracking = false
        #if DEBUG
        proof = TaskSelectionGestureProof()
        #endif
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, state != .failed else { return }
        let point = touch.location(in: nil)
        recordPosition(point)
        if state == .possible {
            let dx = point.x - initial.x, dy = point.y - initial.y
            guard max(abs(dx), abs(dy)) > 10 else { return }
            guard dx > abs(dy) else { state = .failed; return }
            horizontal = true
            store?.isSelectionSwipeActive = true
            state = .began
        }
        if horizontal, !crossedThreshold {
            updateSwipeFeedback(at: point)
            let dx = point.x - initial.x
            guard dx >= viewport.width * 0.25 else { return }
            crossedThreshold = true
            freezeScrolling(in: view)
            #if DEBUG
            proof.crossingDistance = dx
            proof.columnWidth = viewport.width
            #endif
            let token = generation
            let selectionGeneration = store?.taskSelectionGeneration
            let wasEditing = store?.rowEditing != nil
            let initialIDs = touched
            if !wasEditing {
                guard store?.activateSelectionGesture(initialIDs) == true else { state = .cancelled; finish(); return }
                tracking = true
            }
            preparation = Task { [weak self] in
                guard let self, token == self.generation, let store = self.store,
                      selectionGeneration == store.taskSelectionGeneration else { return }
                if wasEditing {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_EDITOR_DELAY"] == "1" {
                        try? await Task.sleep(for: .seconds(3))
                    }
                    #endif
                    guard token == self.generation, !Task.isCancelled,
                          selectionGeneration == store.taskSelectionGeneration else { return }
                    let ready = await store.beginSelectionGesture(initialIDs)
                    guard token == self.generation else { return }
                    if !ready { self.state = .cancelled; self.finish(); return }
                    await self.waitForCollapsedRows()
                    guard token == self.generation, !Task.isCancelled,
                          selectionGeneration == store.taskSelectionGeneration else { return }
                    self.frozenRows = self.rows
                    self.touched = initialIDs
                    let low = max(self.viewport.minY, self.traversedY.lowerBound)
                    let high = min(self.viewport.maxY, self.traversedY.upperBound)
                    for row in self.frozenRows where row.bounds.maxY >= low && row.bounds.minY <= high {
                        self.touched.insert(row.id)
                    }
                    self.previousY = self.latest.y
                    if !self.released { self.freezeScrolling(in: self.view) }
                }
                guard selectionGeneration == store.taskSelectionGeneration else { return }
                self.tracking = true
                store.addToSelection(self.touched)
                self.updateSwipeFeedback(at: self.latest)
                #if DEBUG
                self.recordProof(touch)
                if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1", !self.released {
                    do {
                        let id = UUID()
                        let timestamp = String(Int(store.currentDate.timeIntervalSince1970))
                        _ = try await TaskChampionReplica(directory: store.directory).create(id: id, attributes: [
                            "description": "Arrived while selecting", "status": "pending", "entry": timestamp, "modified": timestamp
                        ])
                        await store.reload()
                        self.proof.refreshWhileTouchDown = !self.released && store.tasks.contains { $0.id == id }
                        self.recordProof(touch)
                    } catch { store.error = error.localizedDescription }
                }
                #endif
                guard token == self.generation, !Task.isCancelled else { return }
                if self.released { self.release() }
            }
        }
        if state == .began || state == .changed {
            let low = max(viewport.minY, min(previousY, point.y))
            let high = min(viewport.maxY, max(previousY, point.y))
            for row in frozenRows where row.bounds.maxY >= low && row.bounds.minY <= high { touched.insert(row.id) }
            if tracking, store?.isSelectionGestureActive == true { store?.addToSelection(touched) }
            updateSwipeFeedback(at: point)
            #if DEBUG
            recordProof(touch)
            #endif
            previousY = point.y
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { recordPosition(touch.location(in: nil)) }
        if state == .began || state == .changed { state = .ended; release() }
        else { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
        finish()
    }

    override func reset() {
        super.reset()
        release()
    }

    func updateRows(_ rows: [TaskSelectionRow]) {
        self.rows = rows
        #if DEBUG
        if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1" {
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.generation else { return }
                self.recordTranslationProof()
            }
        }
        #endif
        if rowsAreCollapsed {
            collapsedLayout?.resume()
            collapsedLayout = nil
        }
    }

    private var rowsAreCollapsed: Bool {
        !rows.contains(where: \.isEditing) && (!rows.isEmpty || store?.visibleTasks.isEmpty == true)
    }

    private func waitForCollapsedRows() async {
        guard !rowsAreCollapsed else { return }
        await withCheckedContinuation { collapsedLayout = $0 }
    }

    private func recordPosition(_ point: CGPoint) {
        latest = point
        traversedY = min(traversedY.lowerBound, point.y)...max(traversedY.upperBound, point.y)
    }

    private func updateSwipeFeedback(at point: CGPoint) {
        guard let store, !released, store.rowEditing == nil, tracking || !crossedThreshold else { return }
        guard let row = frozenRows.first(where: { $0.bounds.minY <= point.y && $0.bounds.maxY >= point.y }),
              store.visibleTasks.contains(where: { $0.id == row.id && $0.canComplete }) else {
            store.selectionSwipe = nil
            return
        }
        store.selectionSwipe = TaskSelectionSwipe(rowID: row.rowID, translation: max(0, point.x - initial.x))
    }

    func finish() {
        generation += 1
        collapsedLayout?.resume()
        collapsedLayout = nil
        preparation?.cancel()
        preparation = nil
        release()
    }

    private func release() {
        released = true
        for (scroll, enabled, _) in scrollViews { scroll.isScrollEnabled = enabled }
        scrollViews = []
        store?.endSelectionGesture()
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            self.store?.isSelectionSwipeActive = false
        }
    }

    private func freezeScrolling(in view: UIView?) {
        guard let view else { return }
        if let scroll = view as? UIScrollView, scroll.window != nil,
           scroll.convert(scroll.bounds, to: nil).intersects(viewport) {
            if !scrollViews.contains(where: { $0.0 === scroll }) {
                scrollViews.append((scroll, scroll.isScrollEnabled, scroll.contentOffset))
            }
            scroll.isScrollEnabled = false
        }
        for child in view.subviews { freezeScrolling(in: child) }
    }

    #if DEBUG
    private func recordTranslationProof() {
        guard ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1",
              !released, store?.isSelectionGestureActive == true else { return }
        var maximum = proof.maximumRowTranslation
        for current in rows {
            guard let original = frozenRows.first(where: { $0.rowID == current.rowID }) else { continue }
            maximum = max(maximum, current.bounds.minX - original.bounds.minX)
        }
        guard maximum > proof.maximumRowTranslation else { return }
        proof.maximumRowTranslation = maximum
        publishProof()
    }

    private func publishProof() {
        if let data = try? JSONEncoder().encode(proof) { store?.selectionGestureProof = String(decoding: data, as: UTF8.self) }
    }

    private func recordProof(_ touch: UITouch) {
        guard ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1", let store,
              !released, touch.phase != .ended, touch.phase != .cancelled else { return }
        if store.isSelectionGestureActive, !store.selectedTaskIDs.isEmpty { proof.selectedWhileTouchDown = true }
        proof.maximumSelectedWhileTouchDown = max(proof.maximumSelectedWhileTouchDown, store.selectedTaskIDs.count)
        let liveScrolls = scrollViews.filter { $0.0.window != nil }
        proof.scrollingDisabled = !liveScrolls.isEmpty && liveScrolls.allSatisfy { !$0.0.isScrollEnabled }
        proof.offsetsStable = proof.offsetsStable && liveScrolls.allSatisfy { $0.0.contentOffset == $0.2 }
        proof.rowsStable = proof.rowsStable && rows.allSatisfy { current in
            guard let original = frozenRows.first(where: { $0.rowID == current.rowID }) else { return true }
            return abs(current.bounds.minY - original.bounds.minY) < 1
        }
        publishProof()
    }
    #endif

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isTaskListContent(touch.view)
    }

    private func isTaskListContent(_ view: UIView?) -> Bool {
        var ancestor = view
        while let current = ancestor {
            if current is UITextView || current is UITextField { return false }
            if let scroll = current as? UIScrollView,
               scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 1 { return false }
            if current.accessibilityIdentifier == "task-list" || current.accessibilityIdentifier == "upcoming-list" { return true }
            ancestor = current.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard otherGestureRecognizer is UIPanGestureRecognizer,
              !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer),
              let view = otherGestureRecognizer.view, isTaskListContent(view) else { return false }
        return view.convert(view.bounds, to: nil).intersects(viewport)
    }

}

#if DEBUG
private struct TaskSelectionGestureProof: Codable {
    var crossingDistance: CGFloat = 0
    var columnWidth: CGFloat = 0
    var selectedWhileTouchDown = false
    var maximumSelectedWhileTouchDown = 0
    var maximumRowTranslation: CGFloat = 0
    var scrollingDisabled = false
    var offsetsStable = true
    var rowsStable = true
    var refreshWhileTouchDown = false
}
#endif
