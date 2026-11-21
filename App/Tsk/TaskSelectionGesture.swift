import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import TskCore

struct TaskSelectionRow: Equatable {
    let id: UUID
    let rowID: String
    let bounds: CGRect
    let isEditing: Bool

    static let slotWidth: CGFloat = 56
    var selectionSlot: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: Self.slotWidth, height: bounds.height)
    }

    var dragStartX: CGFloat { selectionSlot.maxX + 48 }
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
    let rows: [TaskSelectionRow]

    func makeUIView(context: Context) -> SelectionAnchor {
        let view = SelectionAnchor()
        view.recognizer.store = store
        view.recognizer.scope = scope
        scope.selectionRecognizer = view.recognizer
        return view
    }

    func updateUIView(_ view: SelectionAnchor, context: Context) {
        view.recognizer.viewport = viewport
        view.recognizer.rows = rows
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
    weak var scope: TaskSelectionScope?
    var viewport = CGRect.zero
    var rows: [TaskSelectionRow] = []
    private weak var activeTouch: UITouch?
    private var frozenRows: [TaskSelectionRow] = []
    private var previousY: CGFloat = 0
    private var currentRowID: String?
    private let feedback = UISelectionFeedbackGenerator()
    #if DEBUG
    private weak var scroll: UIScrollView?
    private var originalOffset = CGPoint.zero
    private let recordsProof = ProcessInfo.processInfo.environment["TSK_TEST_SELECTION_GESTURE"] == "1"
    private var proof = TaskSelectionGestureProof()
    #endif

    init() {
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil, touches.count == 1, let touch = touches.first, let store,
              let row = eligibleRow(at: touch.location(in: nil)), store.activateSelectionGesture(startingAt: row.id) else {
            state = activeTouch == nil ? .failed : .cancelled
            finish()
            return
        }
        activeTouch = touch
        frozenRows = rows
        previousY = touch.location(in: nil).y
        currentRowID = row.rowID
        store.isSelectionPressActive = true
        #if DEBUG
        scroll = scope?.list
        originalOffset = scroll?.contentOffset ?? .zero
        proof = TaskSelectionGestureProof()
        proof.activationDuration = ProcessInfo.processInfo.systemUptime - touch.timestamp
        proof.columnWidth = row.selectionSlot.width
        #endif
        feedback.prepare()
        state = .began
        selectionChanged()
        #if DEBUG
        recordProof(touch)
        #endif
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        visitRows(at: touch.location(in: nil).y)
        state = .changed
        #if DEBUG
        recordProof(touch)
        #endif
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        visitRows(at: touch.location(in: nil).y)
        state = .ended
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
        finish()
    }

    override func reset() {
        super.reset()
        finish()
    }

    private func visitRows(at y: CGFloat) {
        guard store?.isSelectionGestureActive == true else { return }
        let down = previousY <= y
        let low = max(viewport.minY, min(previousY, y))
        let high = min(viewport.maxY, max(previousY, y))
        let crossed = frozenRows.filter { $0.bounds.maxY > low && $0.bounds.minY <= high }
            .sorted { down ? $0.bounds.minY < $1.bounds.minY : $0.bounds.minY > $1.bounds.minY }
        var visits: [TaskSelectionVisit] = []
        for row in crossed where row.rowID != currentRowID {
            visits.append(TaskSelectionVisit(rowID: row.rowID, taskID: row.id, moving: down ? .next : .previous))
            currentRowID = row.rowID
        }
        currentRowID = frozenRows.first { $0.bounds.minY <= y && y < $0.bounds.maxY && viewport.minY <= y && y < viewport.maxY }?.rowID
        previousY = y
        if !visits.isEmpty, store?.enterSelectionRows(visits) == true { selectionChanged() }
    }

    private func selectionChanged() {
        feedback.selectionChanged()
        feedback.prepare()
    }

    func finish() {
        guard !frozenRows.isEmpty else { return }
        activeTouch = nil
        frozenRows = []
        store?.endSelectionGesture()
        store?.isSelectionPressActive = false
    }

    private func eligibleRow(at point: CGPoint) -> TaskSelectionRow? {
        guard let store, viewport.contains(point), store.rowEditing == nil, !store.isSaving,
              store.taskDrag == nil, store.selectionDateField == nil, store.presentedTaskPanels.isEmpty,
              let row = rows.first(where: { !$0.isEditing && $0.selectionSlot.contains(point) }),
              store.visibleTasks.contains(where: { $0.id == row.id && $0.canComplete }) else { return nil }
        return row
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let list = scope?.list, touch.view?.isDescendant(of: list) == true else { return false }
        return eligibleRow(at: touch.location(in: nil)) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other === scope?.list?.panGestureRecognizer
    }

    #if DEBUG
    private func recordProof(_ touch: UITouch) {
        guard recordsProof, let store,
              activeTouch === touch, touch.phase != .ended, touch.phase != .cancelled else { return }
        proof.selectedWhileTouchDown = proof.selectedWhileTouchDown || !store.selectedTaskIDs.isEmpty
        proof.maximumSelectedWhileTouchDown = max(proof.maximumSelectedWhileTouchDown, store.selectedTaskIDs.count)
        proof.scrollingDisabled = scroll?.isScrollEnabled == false
        proof.offsetsStable = proof.offsetsStable && scroll?.contentOffset == originalOffset
        proof.rowsStable = proof.rowsStable && rows.allSatisfy { current in
            guard let original = frozenRows.first(where: { $0.rowID == current.rowID }) else { return true }
            return abs(current.bounds.minY - original.bounds.minY) < 1 && abs(current.bounds.minX - original.bounds.minX) < 1
        }
        if let data = try? JSONEncoder().encode(proof) { store.selectionGestureProof = String(decoding: data, as: UTF8.self) }
    }

    #endif
}

#if DEBUG
private struct TaskSelectionGestureProof: Codable {
    var activationDuration: TimeInterval = 0
    var columnWidth: CGFloat = 0
    var selectedWhileTouchDown = false
    var maximumSelectedWhileTouchDown = 0
    var scrollingDisabled = false
    var offsetsStable = true
    var rowsStable = true
}
#endif
