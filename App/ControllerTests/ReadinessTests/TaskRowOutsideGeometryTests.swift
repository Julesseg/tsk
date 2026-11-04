import Foundation
import CoreGraphics
import Testing

@Suite struct TaskRowOutsideGeometryProof {
    struct Tree {
        var nodes: [TaskRowOutsideGeometry.Node] = []
        let frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        mutating func replace(_ index: Int, type: TaskRowOutsideGeometry.ElementType? = nil, frame: CGRect? = nil) {
            let node = nodes[index]
            nodes[index] = .init(value: .init(elementType: type ?? node.value.elementType, identifier: node.value.identifier,
                                             frame: frame ?? node.value.frame, isEnabled: node.value.isEnabled),
                                ancestors: node.ancestors, path: node.path)
        }
        @discardableResult mutating func add(_ type: TaskRowOutsideGeometry.ElementType, _ frame: CGRect,
                                             _ identifier: String = "", parent: Int? = nil, enabled: Bool = true) -> Int {
            let ancestors = parent.map { nodes[$0].ancestors + [$0] } ?? []
            let siblings = nodes.filter { $0.ancestors == ancestors }.count
            let path = parent.map { nodes[$0].path + [siblings] } ?? []
            nodes.append(.init(value: .init(elementType: type, identifier: identifier, frame: frame, isEnabled: enabled),
                               ancestors: ancestors, path: path))
            return nodes.count - 1
        }
        static func row(cell: CGRect, field: CGRect, taskID: String = "A0000000-0000-0000-0000-000000000001") -> Self {
            var tree = Self()
            let app = tree.add(.unclassified, tree.frame)
            let window = tree.add(.window, tree.frame, parent: app)
            tree.add(.navigationBar, CGRect(x: 0, y: 62, width: 440, height: 54), parent: window)
            tree.add(.tabBar, CGRect(x: 0, y: 873, width: 440, height: 83), parent: window)
            let list = tree.add(.collectionView, tree.frame, "task-list", parent: window)
            let row = tree.add(.cell, cell, parent: list)
            tree.add(.textField, field, "task-description", parent: row)
            tree.add(.other, cell, "task-row-editor", parent: row)
            tree.add(.button, CGRect(x: 8, y: cell.minY + 11, width: 44, height: 44),
                     "complete-task-row-" + taskID, parent: row)
            let neighbour = tree.add(.cell, CGRect(x: 0, y: cell.maxY, width: 440, height: 235.7), parent: list)
            tree.add(.button, CGRect(x: 56, y: cell.maxY + 4, width: 372, height: 44),
                     "task-A0000000-0000-0000-0000-000000000002", parent: neighbour)
            tree.add(.button, CGRect(x: 0, y: 0, width: 440, height: cell.minY), "task-row-outside", parent: window)
            tree.add(.button, CGRect(x: 0, y: cell.maxY, width: 440, height: max(0, 956 - cell.maxY)),
                     "task-row-outside", parent: window)
            let toolbar = tree.add(.toolbar, tree.frame, parent: window)
            tree.add(.other, tree.frame, parent: toolbar)
            let placeholder = tree.add(.window, tree.frame, parent: app)
            tree.add(.other, tree.frame, parent: placeholder)
            return tree
        }

        @discardableResult mutating func keyboard(bounded: Bool = true) -> (window: Int, envelope: Int, seed: Int) {
            let window = add(.window, frame, parent: 0)
            let wrapper = add(.other, frame, parent: window)
            let envelope = bounded ? add(.other, CGRect(x: 0, y: 609, width: 440, height: 347), parent: wrapper) : wrapper
            let assistant = add(.other, CGRect(x: 0, y: 609, width: 440, height: 44), "SystemInputAssistantView", parent: envelope)
            for (index, label) in ["I", "The", "I’m"].enumerated() {
                add(.button, CGRect(x: CGFloat(index) * 440 / 3, y: 609, width: 440 / 3, height: 44), label, parent: assistant)
            }
            let host = add(.other, CGRect(x: 0, y: 653, width: 440, height: 245), parent: envelope)
            let seed = add(.keyboard, CGRect(x: 0, y: 653, width: 440, height: 245), parent: host)
            add(.other, CGRect(x: 0, y: 609, width: 440, height: 348), parent: envelope)
            let footer = add(.other, CGRect(x: 0, y: 653, width: 440, height: 303), parent: envelope)
            add(.button, CGRect(x: 2.5, y: 887.7, width: 80.1, height: 68.7), "Emoji", parent: footer)
            add(.button, CGRect(x: 357.4, y: 887.4, width: 80.1, height: 68.7), "dictation", parent: footer)
            return (window, envelope, seed)
        }
    }

    @Test func recordedTallOccurrenceOnlyAdmitsTheBodyBelowItsFullCell() throws {
        let tree = Tree.row(cell: CGRect(x: 0, y: 116, width: 440, height: 729),
                            field: CGRect(x: 78, y: 120, width: 350, height: 175),
                            taskID: "317F6B43-21B9-477D-86DE-920100159891")
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        #expect(CGRect(x: 0, y: 845, width: 440, height: 28).contains(geometry.target))
        #expect(geometry.target.midY > 845 && geometry.target.midY < 873)
        #expect(!geometry.target.contains(CGPoint(x: 220, y: 31)))
    }

    @Test func recordedKeyboardSiblingsAreExcludedWithoutBlockingTheRemainingBody() throws {
        var tree = Tree.row(cell: CGRect(x: 0, y: 117, width: 440, height: 204),
                            field: CGRect(x: 56, y: 121, width: 372, height: 20))
        tree.keyboard()
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        #expect(CGRect(x: 0, y: 321, width: 440, height: 288).contains(geometry.target))
        #expect(!geometry.target.intersects(CGRect(x: 0, y: 609, width: 440, height: 347)))
        #expect(geometry.obstructions.contains { $0.contains(CGRect(x: 0, y: 609, width: 440, height: 347)) })
    }

    static func recordedPadColumn() -> Tree {
        var tree = Tree()
        let windowFrame = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let column = CGRect(x: 0, y: 0, width: 360, height: 1032)
        let app = tree.add(.unclassified, windowFrame)
        let window = tree.add(.window, windowFrame, parent: app)
        tree.add(.navigationBar, CGRect(x: 0, y: 32, width: 360, height: 54), parent: window)
        tree.add(.navigationBar, CGRect(x: 0, y: 32, width: 1376, height: 54), parent: window)
        tree.add(.tabBar, CGRect(x: 0, y: 955, width: 1376, height: 77), parent: window)
        let list = tree.add(.collectionView, column, "task-list", parent: window)
        let cell = tree.add(.cell, CGRect(x: 0, y: 86, width: 360, height: 204), parent: list)
        tree.add(.textField, CGRect(x: 56, y: 90, width: 292, height: 20), "task-description", parent: cell)
        tree.add(.other, CGRect(x: 0, y: 86, width: 360, height: 204), "task-row-editor", parent: cell)
        tree.add(.button, CGRect(x: 8, y: 97, width: 44, height: 44),
                 "complete-task-row-A0000000-0000-0000-0000-000000000001", parent: cell)
        let neighbour = tree.add(.cell, CGRect(x: 0, y: 290, width: 360, height: 52), parent: list)
        tree.add(.button, CGRect(x: 56, y: 294, width: 292, height: 44),
                 "task-A0000000-0000-0000-0000-000000000002", parent: neighbour)
        for frame in [CGRect(x: 0, y: 0, width: 1376, height: 86),
                      CGRect(x: 0, y: 86, width: 8, height: 204),
                      CGRect(x: 348, y: 86, width: 1028, height: 204),
                      CGRect(x: 0, y: 290, width: 1376, height: 742)] {
            tree.add(.button, frame, "task-row-outside", parent: window)
        }
        for frame in [column, windowFrame, windowFrame] {
            let toolbar = tree.add(.toolbar, frame, parent: window)
            tree.add(.other, frame, parent: toolbar)
        }
        let placeholder = tree.add(.window, windowFrame, parent: app)
        tree.add(.other, windowFrame, parent: placeholder)
        return tree
    }

    @Test func recordedPadColumnOnlyAdmitsItsOwnedListBody() throws {
        let tree = Self.recordedPadColumn()
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.nodes[0].value.frame, nodes: tree.nodes)
        #expect(CGRect(x: 0, y: 290, width: 360, height: 665).contains(geometry.target))
    }

    @Test func columnSpanningToolbarStillExcludesItsActionableContents() throws {
        var tree = Self.recordedPadColumn()
        let toolbar = try #require(tree.nodes.firstIndex {
            $0.value.elementType == .toolbar && $0.value.frame.width == 360
        })
        tree.add(.button, CGRect(x: 0, y: 290, width: 360, height: 665), "toolbar-action", parent: toolbar)
        #expect(throws: TaskRowOutsideGeometry.Failure.self) {
            try TaskRowOutsideGeometry.admit(applicationFrame: tree.nodes[0].value.frame, nodes: tree.nodes)
        }
    }

    @Test func boundedToolbarStillExcludesItsVisibleBar() throws {
        var tree = Self.recordedPadColumn()
        let window = try #require(tree.nodes.firstIndex { $0.value.elementType == .window })
        let bar = CGRect(x: 0, y: 290, width: 360, height: 80)
        tree.add(.toolbar, bar, parent: window)
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.nodes[0].value.frame, nodes: tree.nodes)
        #expect(!geometry.target.intersects(bar))
        #expect(geometry.obstructions.contains(bar))
        #expect(CGRect(x: 0, y: 370, width: 360, height: 585).contains(geometry.target))
    }

    enum ForeignSurface: CaseIterable {
        case collectionInEnvelope, menuInEnvelope, unrelatedButton, visibleSpill, invalidControl
        case invalidAncestor, unboundedAncestor, semanticAncestor, unclassifiedAncestor, wholeWindowOnly
    }

    @Test(arguments: ForeignSurface.allCases)
    func keyboardOcclusionCannotExemptUnrelatedOrUnboundedForeignSurfaces(_ surface: ForeignSurface) {
        var tree = Tree.row(cell: CGRect(x: 0, y: 117, width: 440, height: 204),
                            field: CGRect(x: 56, y: 121, width: 372, height: 20))
        let input = tree.keyboard(bounded: surface != .wholeWindowOnly)
        switch surface {
        case .collectionInEnvelope:
            tree.add(.collectionView, CGRect(x: 0, y: 700, width: 440, height: 100), parent: input.envelope)
        case .menuInEnvelope:
            tree.add(.menu, CGRect(x: 0, y: 700, width: 440, height: 100), parent: input.envelope)
        case .unrelatedButton:
            tree.add(.button, CGRect(x: 0, y: 700, width: 440, height: 100), parent: input.window)
        case .visibleSpill:
            tree.add(.button, CGRect(x: 0, y: 580, width: 440, height: 80), parent: input.envelope)
        case .invalidControl:
            tree.add(.button, CGRect(x: CGFloat.nan, y: 700, width: 440, height: 100), parent: input.envelope)
        case .invalidAncestor:
            tree.replace(input.envelope, frame: CGRect(x: CGFloat.nan, y: 609, width: 440, height: 347))
        case .unboundedAncestor:
            tree.replace(input.envelope, frame: CGRect(x: 0, y: 0, width: 880, height: 1912))
        case .semanticAncestor:
            tree.replace(input.envelope, type: .toolbar)
        case .unclassifiedAncestor:
            tree.replace(input.envelope, type: .unclassified)
        case .wholeWindowOnly:
            break
        }
        #expect(throws: TaskRowOutsideGeometry.Failure.self) {
            try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        }
    }

    @Test func barePublicKeyboardDoesNotRequireANewSiblingEnvelope() throws {
        var tree = Tree.row(cell: CGRect(x: 0, y: 117, width: 440, height: 204),
                            field: CGRect(x: 56, y: 121, width: 372, height: 20))
        let window = tree.add(.window, tree.frame, parent: 0)
        let wrapper = tree.add(.other, tree.frame, parent: window)
        tree.add(.keyboard, CGRect(x: 0, y: 653, width: 440, height: 245), parent: wrapper)
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        #expect(!geometry.target.intersects(CGRect(x: 0, y: 653, width: 440, height: 245)))
        #expect(geometry.target.minY >= 321 && geometry.target.maxY <= 653)
    }

    @Test func calendarCellAndControlsCannotBecomeAnOutsideSaveTarget() throws {
        var tree = Tree.row(cell: CGRect(x: 0, y: 400, width: 440, height: 216),
                            field: CGRect(x: 56, y: 404, width: 372, height: 20))
        let list = try #require(tree.nodes.firstIndex { $0.value.identifier == "task-list" })
        let calendarFrame = CGRect(x: 0, y: 116, width: 440, height: 284)
        let calendar = tree.add(.cell, calendarFrame, parent: list)
        tree.add(.button, CGRect(x: 16, y: 150, width: 200, height: 44), "calendar-event", parent: calendar)
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        #expect(!geometry.target.intersects(calendarFrame))
        #expect(geometry.target.minY >= 616 && geometry.target.maxY <= 873)
    }

    @Test func partlyOffscreenActiveCellIsExcludedWithoutClippingItsIdentity() throws {
        let cell = CGRect(x: 0, y: 773.6666666667, width: 440, height: 551.6666666667)
        var tree = Tree.row(cell: cell, field: CGRect(x: 78, y: 790, width: 350, height: 290))
        let list = try #require(tree.nodes.firstIndex { $0.value.identifier == "task-list" })
        tree.replace(list, frame: CGRect(x: 0, y: 0, width: 440, height: 861))
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: tree.frame, nodes: tree.nodes)
        #expect(geometry.cellFrame == cell)
        #expect(!geometry.target.intersects(cell))
        #expect(geometry.target.minY >= 116 && geometry.target.maxY <= cell.minY)
    }

    @Test func emptyApplicationUsesOnlyItsOwnedOffsetWindow() throws {
        var tree = Tree.row(cell: CGRect(x: 0, y: 116, width: 440, height: 729),
                            field: CGRect(x: 78, y: 120, width: 350, height: 175))
        for index in tree.nodes.indices {
            tree.replace(index, frame: tree.nodes[index].value.frame.offsetBy(dx: 30, dy: 40))
        }
        let geometry = try TaskRowOutsideGeometry.admit(applicationFrame: .zero, nodes: tree.nodes)
        #expect(geometry.appFrame == CGRect(x: 30, y: 40, width: 440, height: 956))
        #expect(CGRect(x: 30, y: 885, width: 440, height: 28).contains(geometry.target))
        #expect(geometry.reportedAppFrame == .zero)
    }
}
