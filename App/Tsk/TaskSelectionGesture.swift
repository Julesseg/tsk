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
    let scope: TaskSelectionScope
    let viewport: CGRect
    let rows: [String: TaskSelectionRow]

    func makeUIView(context: Context) -> SelectionAnchor {
        let view = SelectionAnchor()
        view.recognizer.store = store
        view.recognizer.scope = scope
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

final class TaskSelectionRecognizer: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
    weak var store: TaskStore?
    weak var scope: TaskSelectionScope?
    var viewport = CGRect.zero
    var rows: [TaskSelectionRow] = []
    private var initial = CGPoint.zero
    private var latest = CGPoint.zero
    private var positions: [CGPoint] = []
    private var previousY: CGFloat = 0
    private var frozenRows: [TaskSelectionRow] = []
    private var initialTaskID: UUID?
    private var initialRowID: String?
    private var initialSelection: Set<UUID> = []
    private var rowVisits: [TaskSelectionVisit] = []
    private var currentRowID: String?
    private let feedback = UISelectionFeedbackGenerator()
    private var scrollViews: [(UIScrollView, Bool, CGPoint)] = []
    #if DEBUG
    private var proof = TaskSelectionGestureProof()
    #endif
    private var preparation: Task<Void, Never>?
    private var collapsedLayout: CheckedContinuation<Void, Never>?
    private var generation = 0
    private var released = false
    private var pressStartedAt: TimeInterval = 0
    private weak var activeTouch: UITouch?
    private var tracking = false

    init() {
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = true
        minimumPressDuration = 0.25
        allowableMovement = 10
        addTarget(self, action: #selector(handlePress))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        #if DEBUG
        trace("began", details: ["touches": "\(touches.count)", "activeTouch": "\(activeTouch != nil)", "rows": "\(rows.count)"])
        recordedFirstMovement = false
        #endif
        guard activeTouch == nil, touches.count == 1, let touch = touches.first, let store, !store.isSaving,
              store.selectionDateField == nil else { state = state == .possible ? .failed : .cancelled; finish(); return }
        generation += 1
        preparation?.cancel()
        collapsedLayout?.resume()
        collapsedLayout = nil
        initial = touch.location(in: nil)
        latest = initial
        positions = [initial]
        guard viewport.contains(initial), let row = rows.first(where: { $0.bounds.contains(initial) }),
              store.visibleTasks.contains(where: { $0.id == row.id && $0.canComplete }) else { state = .failed; return }
        activeTouch = touch
        pressStartedAt = touch.timestamp
        initialTaskID = row.id
        initialRowID = row.rowID
        initialSelection = store.selectedTaskIDs
        rowVisits = []
        currentRowID = row.rowID
        feedback.prepare()
        frozenRows = rows
        previousY = initial.y
        released = false
        tracking = false
        #if DEBUG
        proof = TaskSelectionGestureProof()
        #endif
        super.touchesBegan(touches, with: event)
    }

    @objc private func handlePress() {
        #if DEBUG
        if state != .changed { trace("state", details: ["state": "\(state.rawValue)", "activeTouch": "\(activeTouch != nil)", "selecting": "\(store?.isSelectingTasks == true)"]) }
        #endif
        guard let touch = activeTouch else { return }
        let point = touch.location(in: nil)
        recordPosition(point)
        if state == .began {
            guard let store, let initialTaskID,
                  store.visibleTasks.contains(where: { $0.id == initialTaskID && $0.canComplete }) else { state = .cancelled; finish(); return }
            store.isSelectionPressActive = true
            freezeScrolling(in: view)
            #if DEBUG
            proof.activationDuration = ProcessInfo.processInfo.systemUptime - pressStartedAt
            proof.activationDistance = hypot(point.x - initial.x, point.y - initial.y)
            proof.columnWidth = viewport.width
            #endif
            let token = generation
            let selectionGeneration = store.taskSelectionGeneration
            let wasEditing = store.rowEditing != nil
            if !wasEditing {
                guard store.activateSelectionGesture() else { state = .cancelled; finish(); return }
                tracking = true
                replayPositions()
                applySelection()
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
                    let ready = await store.beginSelectionGesture()
                    guard token == self.generation else { return }
                    if !ready { self.state = .cancelled; self.finish(); return }
                    await self.waitForCollapsedRows()
                    guard token == self.generation, !Task.isCancelled,
                          selectionGeneration == store.taskSelectionGeneration else { return }
                    self.frozenRows = self.rows
                    self.replayPositions()
                    if !self.released { self.freezeScrolling(in: self.view) }
                }
                guard selectionGeneration == store.taskSelectionGeneration else { return }
                self.tracking = true
                self.applySelection()
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
            if tracking, store?.isSelectionGestureActive == true {
                recordRowEntries(from: previousY, to: point.y)
                applySelection()
            }
            #if DEBUG
            recordProof(touch)
            #endif
            previousY = point.y
        }
        if state == .ended {
            if tracking, store?.isSelectionGestureActive == true {
                recordRowEntries(from: previousY, to: point.y)
                applySelection()
            }
            release()
        } else if state == .cancelled || state == .failed {
            finish()
        }
    }

    override func reset() {
        #if DEBUG
        trace("reset", details: ["state": "\(state.rawValue)", "touchPhase": "\(activeTouch?.phase.rawValue ?? -1)", "selected": "\(store?.selectedTaskIDs.count ?? -1)"])
        #endif
        super.reset()
        release()
    }

    func updateRows(_ rows: [TaskSelectionRow]) {
        self.rows = rows
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
        positions.append(point)
    }

    private func replayPositions() {
        rowVisits = []
        currentRowID = initialRowID
        for (from, to) in zip(positions, positions.dropFirst()) {
            recordRowEntries(from: from.y, to: to.y)
        }
        previousY = latest.y
    }

    private func recordRowEntries(from: CGFloat, to: CGFloat) {
        let low = max(viewport.minY, min(from, to))
        let high = min(viewport.maxY, max(from, to))
        let crossed = frozenRows.filter { $0.bounds.maxY > low && $0.bounds.minY <= high }
            .sorted { from <= to ? $0.bounds.minY < $1.bounds.minY : $0.bounds.minY > $1.bounds.minY }
        for row in crossed where row.rowID != currentRowID {
            rowVisits.append(TaskSelectionVisit(rowID: row.rowID, taskID: row.id, moving: from <= to ? .next : .previous))
            currentRowID = row.rowID
        }
        currentRowID = frozenRows.first { $0.bounds.minY <= to && to < $0.bounds.maxY && viewport.minY <= to && to < viewport.maxY }?.rowID
    }

    private func applySelection() {
        guard let initialTaskID, let store,
              store.applySelectionGesture(startingAt: initialTaskID, from: initialSelection, entering: rowVisits) else { return }
        feedback.selectionChanged()
        feedback.prepare()
    }

    func finish() {
        #if DEBUG
        trace("finish", details: ["state": "\(state.rawValue)", "activeTouch": "\(activeTouch != nil)"])
        #endif
        generation += 1
        collapsedLayout?.resume()
        collapsedLayout = nil
        preparation?.cancel()
        preparation = nil
        release()
    }

    private func release() {
        released = true
        activeTouch = nil
        for (scroll, enabled, _) in scrollViews { scroll.isScrollEnabled = enabled }
        scrollViews = []
        store?.endSelectionGesture()
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            self.store?.isSelectionPressActive = false
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
            return abs(current.bounds.minY - original.bounds.minY) < 1 && abs(current.bounds.minX - original.bounds.minX) < 1
        }
        publishProof()
    }
    #endif

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_NATIVE_IDENTIFIERS"] == "0" {
            var ancestor = touch.view
            while let current = ancestor {
                if current.accessibilityIdentifier == "task-list" || current.accessibilityIdentifier == "upcoming-list" {
                    current.accessibilityIdentifier = nil
                }
                ancestor = current.superview
            }
        }
        #endif
        let admitted = isTaskListContent(touch.view)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1" {
            var path: [String] = []
            var ancestor = touch.view
            while let current = ancestor, path.count < 12 {
                let enabled = (current as? UIControl).map { " enabled=\($0.isEnabled)" } ?? ""
                path.append("\(type(of: current))\(enabled)")
                ancestor = current.superview
            }
            let point = touch.location(in: nil)
            trace("admission", details: ["admitted": "\(admitted)", "path": path.joined(separator: "/"), "point": "\(point)", "viewport": "\(viewport)", "row": rows.first(where: { $0.bounds.contains(point) })?.rowID ?? "none", "list": scope?.list.map { "\(ObjectIdentifier($0))" } ?? "none"])
        }
        #endif
        return admitted
    }

    #if DEBUG
    private var recordedFirstMovement = false

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !recordedFirstMovement, state == .possible, let touch = touches.first {
            recordedFirstMovement = true
            let point = touch.location(in: nil)
            trace("first-move", details: ["elapsed": "\(touch.timestamp - pressStartedAt)", "distance": "\(hypot(point.x - initial.x, point.y - initial.y))", "point": "\(point)"])
        }
        super.touchesMoved(touches, with: event)
    }

    private func trace(_ phase: String, details: [String: String]) {
        guard ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1" else { return }
        var captured = details
        captured["captureUptime"] = "\(ProcessInfo.processInfo.systemUptime)"
        captured["recognizer"] = "\(ObjectIdentifier(self))"
        captured["scope"] = scope.map { "\(ObjectIdentifier($0))" } ?? "none"
        captured["generation"] = "\(generation)"
        let payload = captured
        Self.traceQueue.async {
            TaskParticipantDiagnostics.event("[DEBUG-pr75-selection]." + phase, details: payload)
        }
    }

    private static let traceQueue = DispatchQueue(label: "tsk.selection-trace")
    #endif

    private func isTaskListContent(_ view: UIView?) -> Bool {
        guard let list = scope?.list else { return false }
        var ancestor = view
        while let current = ancestor {
            if current is UITextView || current is UITextField { return false }
            if let scroll = current as? UIScrollView,
               scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 1 { return false }
            if current === list { return true }
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
    var activationDuration: TimeInterval = 0
    var activationDistance: CGFloat = 0
    var columnWidth: CGFloat = 0
    var selectedWhileTouchDown = false
    var maximumSelectedWhileTouchDown = 0
    var scrollingDisabled = false
    var offsetsStable = true
    var rowsStable = true
    var refreshWhileTouchDown = false
}
#endif
