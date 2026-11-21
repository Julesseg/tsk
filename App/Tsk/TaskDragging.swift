import SwiftUI
import UIKit
import TskCore

struct TaskCalendarDragRow: Equatable {
    let event: CalendarEventSnapshot
    let bounds: CGRect
}

struct TaskCalendarDragRowsKey: PreferenceKey {
    static let defaultValue: [CalendarEventIdentity: TaskCalendarDragRow] = [:]
    static func reduce(value: inout [CalendarEventIdentity: TaskCalendarDragRow], nextValue: () -> [CalendarEventIdentity: TaskCalendarDragRow]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TaskNativeDrag: UIViewRepresentable {
    let store: TaskStore
    let scope: TaskSelectionScope
    let rows: [TaskSelectionRow]
    let eventRows: [TaskCalendarDragRow]
    let reduceMotion: Bool

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        coordinator.reduceMotion = reduceMotion
        coordinator.eventRows = eventRows
        coordinator.updateRows(rows)
        view.resolve = { [weak coordinator, weak scope, weak store] in coordinator?.attach(to: store?.taskDragContext == nil ? nil : scope?.list) }
        view.resolve?()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }

    final class Anchor: UIView {
        var resolve: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); Task { @MainActor [weak self] in self?.resolve?() } }
    }

    final class Coordinator: NSObject, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
        weak var store: TaskStore?
        weak var list: UICollectionView?
        var rows: [TaskSelectionRow] = []
        var eventRows: [TaskCalendarDragRow] = []
        var reduceMotion = false
        private var previousY: CGFloat?
        private var previousCenters: [DayPageItem.ID: CGFloat] = [:]
        private var dropping = false
        private weak var previousDragDelegate: (any UICollectionViewDragDelegate)?
        private weak var previousDropDelegate: (any UICollectionViewDropDelegate)?
        private var wasDragEnabled = false
        #if DEBUG
        private let recordsProof = ProcessInfo.processInfo.environment["TSK_TEST_NATIVE_DRAG"] == "1"
        private var initialCenters: [DayPageItem.ID: CGFloat] = [:]
        private var originalTasks: [TaskRecord] = []
        private var proof = Proof()
        private var reads: [Task<Void, Never>] = []
        #endif

        func attach(to scrollView: UIScrollView?) {
            guard let list = scrollView as? UICollectionView else { detach(); return }
            if self.list !== list {
                detach()
                self.list = list
                previousDragDelegate = list.dragDelegate
                previousDropDelegate = list.dropDelegate
                wasDragEnabled = list.dragInteractionEnabled
            }
            if list.dragDelegate !== self { list.dragDelegate = self }
            if list.dropDelegate !== self { list.dropDelegate = self }
            if !list.dragInteractionEnabled { list.dragInteractionEnabled = true }
        }

        func detach() {
            if let list {
                if list.dragDelegate === self { list.dragDelegate = previousDragDelegate }
                if list.dropDelegate === self { list.dropDelegate = previousDropDelegate }
                list.dragInteractionEnabled = wasDragEnabled
            }
            if !dropping, store?.taskDrag != nil {
                store?.isTaskDragLifted = false
                store?.taskDrag = nil
            }
            list = nil
        }

        func updateRows(_ rows: [TaskSelectionRow]) {
            self.rows = rows
            #if DEBUG
            guard recordsProof, let drag = store?.taskDrag, !dropping, let list, let window = list.window else { return }
            for (target, y) in crossingCenters(in: list, window: window) {
                if case .task(let id) = target, drag.ids.contains(id) { continue }
                if let initial = initialCenters[target.id], abs(y - initial) > 4 {
                    proof.displaced.insert(target.proofID)
                }
            }
            #endif
        }

        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            guard let window = list?.window else { return [] }
            let point = session.location(in: window)
            guard let store, let row = rows.first(where: { $0.bounds.contains(point) }), !row.isEditing,
                  point.x >= row.dragStartX,
                  store.beginTaskDrag(id: row.id) else { return [] }
            guard let drag = store.taskDrag else { return [] }
            previousY = session.location(in: collectionView).y
            previousCenters = Dictionary(uniqueKeysWithValues: crossingCenters(in: collectionView, window: window).map { ($0.target.id, $0.y) })
            dropping = false
            session.localContext = self
            #if DEBUG
            if recordsProof {
                originalTasks = store.tasks.filter { drag.ids.contains($0.id) }
                initialCenters = previousCenters
            }
            proof = Proof()
            proof.nativeSessions = 1
            reads = []
            proof.draggedIDs = drag.ids.map(\.uuidString)
            #endif
            let items = drag.ids.map { id in
                let item = UIDragItem(itemProvider: NSItemProvider(object: id.uuidString as NSString))
                item.localObject = id
                if let target = rows.first(where: { $0.id == id }),
                   let index = collectionView.indexPathForItem(at: collectionView.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), from: window)),
                   let preview = collectionView.cellForItem(at: index)?.snapshotView(afterScreenUpdates: false) {
                    item.previewProvider = {
                        let parameters = UIDragPreviewParameters()
                        parameters.backgroundColor = .systemBackground
                        return UIDragPreview(view: preview, parameters: parameters)
                    }
                }
                return item
            }
            #if DEBUG
            publishProof("begin")
            #endif
            return items
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
            guard store?.taskDrag != nil else { return }
            store?.isTaskDragLifted = true
            #if DEBUG
            proof.lifted = true
            proof.nativeItems = session.items.count
            #endif
        }

        func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .systemBackground
            return parameters
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool { true }
        func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }

        private func trackCrossings(_ session: any UIDropSession) {
            guard let store, let drag = store.taskDrag, !dropping else { return }
            guard let list, let window = list.window else { return }
            let y = session.location(in: list).y
            guard let previousY else { self.previousY = y; return }
            self.previousY = y
            guard y != previousY else { return }
            let centers = crossingCenters(in: list, window: window).filter { target in
                if case .task(let id) = target.target { return !drag.ids.contains(id) }
                return true
            }
            let crossed = centers.compactMap { target -> (target: Crossing, fraction: CGFloat)? in
                let before = previousY - (previousCenters[target.target.id] ?? target.y)
                let after = y - target.y
                guard y > previousY ? before < 0 && after >= 0 : before > 0 && after <= 0 else { return nil }
                return (target.target, before / (before - after))
            }.sorted { $0.fraction < $1.fraction }.map(\.target)
            previousCenters = Dictionary(uniqueKeysWithValues: centers.map { ($0.target.id, $0.y) })
            for target in crossed {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    switch target {
                    case .task(let id): store.taskDrag?.cross(id, direction: y > previousY ? .downward : .upward)
                    case .event(let event): store.taskDrag?.cross(event)
                    }
                }
                #if DEBUG
                if recordsProof {
                    proof.crossed.append(target.proofID)
                    publishProof("cross")
                    let originals = originalTasks
                    reads.append(Task { [weak self] in
                        for original in originals {
                            let saved = try? await store.manager.task(id: original.id)
                            if saved != original { self?.proof.originalsRetainedDuringCrossing = false }
                        }
                    })
                }
                #endif
            }
        }

        private func crossingCenters(in list: UICollectionView, window: UIWindow) -> [(target: Crossing, y: CGFloat)] {
            let taskCenters = rows.map { row in
                (target: Crossing.task(row.id), y: list.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), from: window).y)
            }
            let eventCenters = eventRows.map { row in
                (target: Crossing.event(row.event), y: list.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), from: window).y)
            }
            return taskCenters + eventCenters
        }

        func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
            session.localDragSession?.localContext as? Coordinator === self && store?.taskDrag != nil
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            guard self.collectionView(collectionView, canHandle: session) else { return UICollectionViewDropProposal(operation: .cancel) }
            trackCrossings(session)
            let proposal = UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            proposal.prefersFullSizePreview = true
            return proposal
        }

        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            guard self.collectionView(collectionView, canHandle: coordinator.session), !dropping else { return }
            for item in coordinator.items {
                if let id = item.dragItem.localObject as? UUID, let row = rows.first(where: { $0.id == id }) {
                    coordinator.drop(item.dragItem, to: UIDragPreviewTarget(container: collectionView, center: collectionView.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), from: nil)))
                }
            }
            dropping = true
            #if DEBUG
            publishProof("dropping")
            #endif
            Task { @MainActor in
                #if DEBUG
                for read in reads { await read.value }
                proof.drops += 1
                #endif
                await store?.finishTaskDrop()
                #if DEBUG
                publishProof("dropped")
                #endif
                dropping = false
            }
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
            if store?.isTaskDragLifted == true { store?.isTaskDragLifted = false }
            previousY = nil
            previousCenters = [:]
            if !dropping, store?.taskDrag != nil { store?.taskDrag = nil }
        }

        private enum Crossing {
            case task(UUID)
            case event(CalendarEventSnapshot)

            var id: DayPageItem.ID {
                switch self {
                case .task(let id): .task(id)
                case .event(let event): .event(event.id)
                }
            }

            var proofID: String {
                switch self {
                case .task(let id): id.uuidString
                case .event(let event): "event:" + event.dragAccessibilityID
                }
            }
        }

        #if DEBUG
        private func publishProof(_ phase: String) {
            guard recordsProof else { return }
            proof.phase = phase
            if let data = try? JSONEncoder().encode(proof) { store?.taskDragProof = String(decoding: data, as: UTF8.self) }
        }

        private struct Proof: Codable {
            var phase = ""
            var nativeSessions = 0
            var draggedIDs: [String] = []
            var nativeItems = 0
            var lifted = false
            var crossed: [String] = []
            var displaced: Set<String> = []
            var originalsRetainedDuringCrossing = true
            var drops = 0
        }
        #endif
    }
}
