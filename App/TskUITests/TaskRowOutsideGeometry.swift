import Foundation
import CoreGraphics

struct TaskRowOutsideGeometry: Equatable {
    enum ElementType {
        case other, unclassified, window, cell, collectionView, navigationBar, tabBar, toolbar, keyboard
        case button, `switch`, textField, textView, searchField, link, slider, stepper
        case picker, pickerWheel, datePicker, segmentedControl, scrollBar
        case sheet, popover, alert, dialog, menu
    }
    struct Element {
        let elementType: ElementType
        let identifier: String
        let frame: CGRect
        let isEnabled: Bool
    }
    struct Node {
        let value: Element
        let ancestors: [Int]
        let path: [Int]
    }
    struct Failure: Error { let reason: String }

    let owner: String
    let listIdentifier: String
    let appFrame: CGRect
    let reportedAppFrame: CGRect
    let windowFrame: CGRect
    let listFrame: CGRect
    let cellFrame: CGRect
    let regions: [CGRect]
    let obstructions: [CGRect]
    let target: CGRect

    var diagnostic: String {
        "\(owner) anchor=\(appFrame) viewport=\(appFrame.intersection(windowFrame).intersection(listFrame)) cell=\(cellFrame) target=\(target) obstructions=\(obstructions.count)"
    }

    static func admit(applicationFrame: CGRect, nodes: [Node]) throws -> Self {
        try require(!nodes.isEmpty && nodes.count <= 4096, "snapshot node cap")
        for (index, node) in nodes.enumerated() {
            try require(node.ancestors.allSatisfy { $0 >= 0 && $0 < index }
                        && Set(node.ancestors).count == node.ancestors.count, "invalid snapshot ancestry")
            if let parent = node.ancestors.last {
                try require(nodes[parent].ancestors == Array(node.ancestors.dropLast()), "invalid snapshot ancestry")
            }
        }
        let fields = nodes.indices.filter {
            nodes[$0].value.identifier == "task-description" && nodes[$0].value.isEnabled
                && [.textField, .textView].contains(nodes[$0].value.elementType)
        }
        try require(fields.count == 1, "active row field is ambiguous or unavailable")
        let field = nodes[fields[0]]
        guard let cellIndex = field.ancestors.last(where: { nodes[$0].value.elementType == .cell }),
              let listIndex = field.ancestors.last(where: {
                  nodes[$0].value.elementType == .collectionView
                      && ["task-list", "upcoming-list"].contains(nodes[$0].value.identifier)
              }),
              let windowIndex = field.ancestors.last(where: { nodes[$0].value.elementType == .window }) else {
            throw Failure(reason: "active row has no owned cell, task list or window")
        }
        let cell = nodes[cellIndex], list = nodes[listIndex], window = nodes[windowIndex]
        try require(cell.ancestors.contains(listIndex) && list.ancestors.contains(windowIndex), "row ownership mismatch")
        let editors = nodes.indices.filter {
            nodes[$0].value.identifier == "task-row-editor" && nodes[$0].ancestors.contains(cellIndex)
        }
        try require(editors.count == 1, "expanded row owner is ambiguous")
        try require(finite(applicationFrame) && positive(window.value.frame) && positive(list.value.frame)
                    && positive(cell.value.frame) && positive(field.value.frame), "invalid owner geometry")
        let appFrame = applicationFrame.isEmpty ? window.value.frame : applicationFrame
        try require(list.value.isEnabled, "physical task list is unavailable")
        let viewport = appFrame.intersection(window.value.frame).intersection(list.value.frame)
        try require(positive(viewport), "task list has no visible viewport")
        let metadata = nodes.indices.filter {
            nodes[$0].value.identifier == "task-row-outside" && nodes[$0].value.elementType == .button
                && nodes[$0].ancestors.contains(windowIndex)
        }
        try require(!metadata.isEmpty && metadata.count <= 4, "outside region metadata is unavailable or ambiguous")
        try require(metadata.allSatisfy { finite(nodes[$0].value.frame) }, "invalid outside region metadata")
        let regions = normalized(metadata.map { nodes[$0].value.frame }.filter(positive))
        var taskCells = Set<Int>()
        for node in nodes where TaskRowControlIdentity(node.value.identifier) != nil {
            if let owner = node.ancestors.last(where: { nodes[$0].value.elementType == .cell }),
               nodes[owner].ancestors.contains(listIndex) { taskCells.insert(owner) }
        }
        let actions: Set<ElementType> = [.button, .switch, .textField, .textView, .searchField,
                                                   .link, .slider, .stepper, .picker, .pickerWheel,
                                                   .datePicker, .segmentedControl, .scrollBar]
        let presentations: Set<ElementType> = [.sheet, .popover, .alert, .dialog, .menu]
        let keyboardRoots = Set(nodes.indices.filter {
            nodes[$0].value.elementType == .keyboard || nodes[$0].value.identifier == "inputAssistantView"
        })
        var inputEnvelopes: [(root: Int, window: Int, frame: CGRect)] = []
        for seed in keyboardRoots.sorted() {
            try require(finite(nodes[seed].value.frame), "invalid keyboard geometry")
            guard positive(nodes[seed].value.frame) else { continue }
            guard let inputWindow = nodes[seed].ancestors.last(where: { nodes[$0].value.elementType == .window }) else {
                throw Failure(reason: "keyboard window is unavailable")
            }
            let inputWindowFrame = nodes[inputWindow].value.frame
            try require(positive(inputWindowFrame), "invalid keyboard window geometry")
            let visibleKeyboard = nodes[seed].value.frame.intersection(inputWindowFrame)
            guard positive(visibleKeyboard) else { continue }
            var root = seed
            var envelope = visibleKeyboard
            for ancestor in nodes[seed].ancestors.reversed() {
                guard ancestor != inputWindow, nodes[ancestor].value.elementType == .other else { break }
                let bounds = nodes[ancestor].value.frame
                try require(finite(bounds), "invalid keyboard ancestry geometry")
                guard positive(bounds), !bounds.contains(inputWindowFrame), inputWindowFrame.contains(bounds),
                      bounds.contains(visibleKeyboard), !nodes[listIndex].ancestors.contains(ancestor),
                      !field.ancestors.contains(ancestor) else { break }
                root = ancestor
                envelope = bounds
            }
            inputEnvelopes.append((root, inputWindow, envelope))
        }
        var obstructions = [cell.value.frame]
        obstructions.append(contentsOf: inputEnvelopes.map(\.frame))
        for (index, node) in nodes.enumerated() {
            let value = node.value, frame = value.frame
            if presentations.contains(value.elementType)
                || ["row-parameter-picker", "close-row-parameter"].contains(value.identifier) {
                try require(finite(frame), "invalid presentation geometry")
                try require(!positive(frame.intersection(viewport)), "presented surface obscures outside-save ownership")
            }
            let ownerWindow = node.ancestors.last(where: { nodes[$0].value.elementType == .window })
            if let ownerWindow, ownerWindow != windowIndex && value.elementType == .collectionView {
                try require(finite(frame), "invalid foreign-window surface geometry")
                try require(!positive(frame.intersection(viewport)), "foreign-window surface obscures outside-save ownership")
            }
            if value.elementType == .collectionView && node.ancestors.contains(windowIndex) && index != listIndex
                && !node.ancestors.contains(listIndex) && !list.ancestors.contains(index) {
                try require(finite(frame), "invalid collection geometry")
                try require(!positive(frame.intersection(viewport)), "another collection obscures outside-save ownership")
            }
            if let input = inputEnvelopes.first(where: { index == $0.root || node.ancestors.contains($0.root) }) {
                if actions.contains(value.elementType) {
                    try require(finite(frame), "invalid input control geometry")
                    let visible = frame.intersection(nodes[input.window].value.frame)
                    try require(!positive(visible) || input.frame.contains(visible), "input control spills outside bounded occlusion")
                }
                continue
            }
            if let ownerWindow, ownerWindow != windowIndex && actions.contains(value.elementType) {
                try require(finite(frame), "invalid foreign-window surface geometry")
                try require(!positive(frame.intersection(viewport)), "foreign-window surface obscures outside-save ownership")
            }
            if node.ancestors.contains(windowIndex) && (actions.contains(value.elementType)
                || [.cell, .collectionView, .navigationBar, .tabBar, .toolbar].contains(value.elementType)) {
                try require(finite(frame), "invalid surface geometry")
            }
            guard node.ancestors.contains(windowIndex), positive(frame.intersection(viewport)) else { continue }
            if value.elementType == .navigationBar || value.elementType == .tabBar
                || value.elementType == .toolbar && !frame.contains(viewport) {
                obstructions.append(frame)
            }
            if value.elementType == .navigationBar {
                obstructions.append(CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width,
                                           height: min(viewport.maxY, frame.maxY) - viewport.minY))
            }
            if node.ancestors.contains(cellIndex) || index == cellIndex { continue }
            if node.ancestors.contains(where: { taskCells.contains($0) }) || taskCells.contains(index) { continue }
            if value.elementType == .cell && node.ancestors.contains(listIndex)
                || actions.contains(value.elementType) && value.identifier != "task-row-outside" {
                try require(finite(frame), "invalid actionable geometry")
                obstructions.append(frame)
            }
        }
        obstructions = normalized(obstructions)
        var fragments = regions.map { $0.intersection(viewport) }.filter(positive)
        for obstruction in obstructions {
            fragments = fragments.flatMap { subtract(obstruction, from: $0) }
            try require(fragments.count <= 256, "outside geometry fragment cap")
        }
        let targets = normalized(fragments).sorted {
            let leftArea = $0.width * $0.height, rightArea = $1.width * $1.height
            if leftArea != rightArea { return leftArea > rightArea }
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            if $0.minX != $1.minX { return $0.minX < $1.minX }
            return $0.width < $1.width
        }
        guard let target = targets.first else { throw Failure(reason: "no unobstructed physical outside region") }
        let point = CGPoint(x: target.midX, y: target.midY)
        try require(viewport.contains(point) && !cell.value.frame.contains(point)
                    && regions.contains(where: { $0.contains(point) })
                    && !obstructions.contains(where: { $0.contains(point) }), "outside point is not independently safe")
        let taskIDs = nodes.filter {
            $0.ancestors.contains(cellIndex) && $0.value.identifier.hasPrefix("complete-task-row-")
        }.map { $0.value.identifier }
        try require(Set(taskIDs).count <= 1, "active task identity is ambiguous")
        let owner = "window=\(window.path) list=\(list.value.identifier):\(list.path) cell=\(cell.path) field=\(field.path) task=\(taskIDs.first ?? "unexposed")"
        let current = Self(owner: owner, listIdentifier: list.value.identifier, appFrame: appFrame, reportedAppFrame: applicationFrame, windowFrame: window.value.frame,
                                listFrame: list.value.frame, cellFrame: cell.value.frame,
                                regions: regions, obstructions: obstructions, target: target)
        return current
    }

    private static func finite(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width >= 0 && rect.height >= 0 && !rect.isNull
    }
    private static func positive(_ rect: CGRect) -> Bool { finite(rect) && rect.width > 0 && rect.height > 0 }
    private static func normalized(_ rects: [CGRect]) -> [CGRect] {
        rects.sorted {
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            if $0.minX != $1.minX { return $0.minX < $1.minX }
            if $0.width != $1.width { return $0.width < $1.width }
            return $0.height < $1.height
        }.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
    }
    private static func subtract(_ obstruction: CGRect, from rect: CGRect) -> [CGRect] {
        let cut = rect.intersection(obstruction)
        guard positive(cut) else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: cut.minY - rect.minY),
            CGRect(x: rect.minX, y: cut.maxY, width: rect.width, height: rect.maxY - cut.maxY),
            CGRect(x: rect.minX, y: cut.minY, width: cut.minX - rect.minX, height: cut.height),
            CGRect(x: cut.maxX, y: cut.minY, width: rect.maxX - cut.maxX, height: cut.height)
        ].filter(positive)
    }
    private static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(reason: reason) }
    }
}
