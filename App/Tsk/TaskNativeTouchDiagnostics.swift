#if DEBUG && targetEnvironment(simulator)
import Foundation
import ObjectiveC
import UIKit
import MachO
import Darwin

private struct NativeTouchRecord: Codable, Sendable {
    let sequence: Int
    let stage: String
    let uptime: TimeInterval
    let wallTime: TimeInterval
    let details: [String: String]
    let ancestors: [[String: String]]
    let recognizers: [[String: String]]
    let origins: [[String: String]]
}

private struct NativeTouchExport: Codable, Sendable {
    let schema: Int
    let session: String
    let replica: String
    let processID: Int32
    let evictedRecords: Int
    let alphaMutationCount: Int
    let alphaDroppedMutations: Int
    let records: [NativeTouchRecord]
    let images: [NativeTouchImage]
    var symbols: [NativeTouchSymbol] = []
}

private struct NativeTouchSymbol: Codable, Sendable {
    let address: String
    let image: String?
    let imageAddress: String?
    let symbol: String?
    let symbolAddress: String?
}

private struct NativeTouchImage: Codable, Sendable {
    let path: String
    let address: String
    let uuid: String?
}

@MainActor
enum TaskNativeTouchDiagnostics {
    private static var installed = false
    private static var session = ""
    private static var replica = ""
    private static var records: [NativeTouchRecord] = []
    private static var sequence = 0
    private static var evictedRecords = 0
    private static var exportPending = false
    private static var lastExportedSequence = 0
    private static var expandedOwner: String?
    private static var keyboardApplyOrdinals: [String: Int] = [:]
    private static var mainRebuildRequestOrdinals: [String: Int] = [:]
    private static var touchOrigins: [ObjectIdentifier: TouchOrigin] = [:]
    private static var sourceCandidates: [SourceCandidate] = []
    private static var droppedOriginCaptures = 0
    private static var alphaTargets: [ObjectIdentifier: AlphaTarget] = [:]
    private static var alphaTargetOrder: [ObjectIdentifier] = []
    private static var alphaInProgress = false
    private static var alphaMutationCount = 0
    private static var alphaDroppedMutations = 0
    private static var lastEventStage = "none"
    private static var lastEventPhase = "none"
    private static var images: [NativeTouchImage] = []
    private static weak var activeEditing: TaskRowEditing?
    private static weak var activeStore: TaskStore?
    private static var outsideRequest: Int?
    private static var destination: URL?
    private static let output = DispatchQueue(label: "tsk.pr77.native-touch-export", qos: .utility)

    static var isRecording: Bool { installed }

    static func register(store: TaskStore) {
        guard installed || ProcessInfo.processInfo.environment["TSK_TEST_NATIVE_TOUCH_TRACE"] != nil else { return }
        activeStore = store
    }

    static func outsideTap(_ point: CGPoint, editing: TaskRowEditing?) -> Int {
        guard installed else { return 0 }
        let request = sequence + 1
        outsideRequest = request
        append("outside.callback", details: state(editing).merging([
            "request": String(request), "point": NSCoder.string(for: point),
            "bounds": editing.map { NSCoder.string(for: $0.bounds) } ?? "unavailable",
            "accepted": String(editing.map { $0.isExpanded && !$0.bounds.contains(point) } ?? false)
        ]) { _, value in value })
        return request
    }

    static func outsideFinished(_ request: Int) {
        if outsideRequest == request { outsideRequest = nil }
    }

    static func closeRequested(_ editing: TaskRowEditing) -> Int? {
        guard installed else { return nil }
        let request = sequence + 1
        append("close.request", details: state(editing).merging([
            "request": String(request), "outsideRequest": outsideRequest.map(String.init) ?? "none"
        ]) { _, value in value })
        return request
    }

    static func closeTaskStarted(_ request: Int?, editing: TaskRowEditing) {
        guard installed else { return }
        append("close.task", details: state(editing).merging([
            "request": request.map(String.init) ?? "none"
        ]) { _, value in value })
    }

    static func save(_ stage: String, editing: TaskRowEditing, request: Int?, outcome: String = "none") {
        guard installed else { return }
        append("save." + stage, details: state(editing).merging([
            "request": request.map(String.init) ?? "none", "outcome": outcome
        ]) { _, value in value })
        exportAfterDispatch()
    }

    private static func state(_ editing: TaskRowEditing? = activeEditing) -> [String: String] {
        ["owner": editing.map(identity) ?? "unavailable", "expandedOwner": expandedOwner ?? "nil",
         "editingSaving": editing.map { String($0.isSaving) } ?? "unavailable",
         "storeSaving": activeStore.map { String($0.isSaving) } ?? "unavailable",
         "expanded": editing.map { String($0.isExpanded) } ?? "unavailable",
         "supportingPanel": editing.map { $0.supportingPanel?.id ?? "nil" } ?? "unavailable",
         "parameter": editing.map { $0.parameter?.rawValue ?? "nil" } ?? "unavailable"]
    }

    private static func trackAlpha(_ collection: UICollectionView, touch: String, sequence: Int, generation: TimeInterval) {
        let key = ObjectIdentifier(collection)
        alphaTargets[key] = AlphaTarget(collection, touch: touch, sequence: sequence, generation: generation)
        alphaTargetOrder.removeAll { $0 == key }
        alphaTargetOrder.append(key)
        if alphaTargetOrder.count > 4 { alphaTargets.removeValue(forKey: alphaTargetOrder.removeFirst()) }
    }

    static func alphaWillChange(_ view: UIView, requested: CGFloat) -> AlphaMutation? {
        guard installed, let target = alphaTargets[ObjectIdentifier(view)], target.collection === view else { return nil }
        guard !alphaInProgress else { alphaDroppedMutations += 1; return nil }
        let old = view.alpha
        guard old != requested, requested < old || target.mutations > 0 else { return nil }
        guard target.mutations < 4, alphaMutationCount < 64 else {
            alphaDroppedMutations += 1
            exportAfterDispatch()
            return nil
        }
        alphaInProgress = true
        target.mutations += 1
        alphaMutationCount += 1
        let details = state().merging([
            "mutation": String(alphaMutationCount), "collection": identity(view),
            "captureSequence": String(target.sequence), "beganGeneration": String(target.generation),
            "touch": target.touch, "oldAlpha": String(describing: old), "requestedAlpha": String(describing: requested),
            "eventStage": lastEventStage, "eventPhase": lastEventPhase,
            "lastReceiptSequence": String(sequence), "droppedMutations": String(alphaDroppedMutations)
        ]) { _, value in value }
        append("alpha.setter.before", details: details)
        return AlphaMutation(details: details, started: ProcessInfo.processInfo.systemUptime)
    }

    static func alphaDidChange(_ view: UIView, mutation: AlphaMutation) {
        let returned = ProcessInfo.processInfo.systemUptime
        let actual = view.alpha
        let stack = Thread.callStackReturnAddresses.prefix(24).map { String($0.uintValue, radix: 16) }
        append("alpha.setter.after", details: mutation.details.merging([
            "actualAlpha": String(describing: actual), "setterReturnedUptime": String(returned),
            "setterSeconds": String(returned - mutation.started), "stack": stack.joined(separator: ","),
            "observationSeconds": String(ProcessInfo.processInfo.systemUptime - returned),
            "stackLimitReached": String(stack.count == 24)
        ]) { _, value in value })
        alphaInProgress = false
        exportAfterDispatch()
    }

    struct AlphaMutation: Sendable {
        let details: [String: String]
        let started: TimeInterval
    }

    private final class AlphaTarget {
        weak var collection: UICollectionView?
        let touch: String
        let sequence: Int
        let generation: TimeInterval
        var mutations = 0

        init(_ collection: UICollectionView, touch: String, sequence: Int, generation: TimeInterval) {
            self.collection = collection
            self.touch = touch
            self.sequence = sequence
            self.generation = generation
        }
    }

    private static func loadedImages() -> [NativeTouchImage] {
        (0..<_dyld_image_count()).compactMap { index in
            guard let header = _dyld_get_image_header(index), let name = _dyld_get_image_name(index) else { return nil }
            var uuid: String?
            if header.pointee.magic == MH_MAGIC_64 {
                var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
                var remaining = Int(UnsafeRawPointer(header).load(as: mach_header_64.self).sizeofcmds)
                for _ in 0..<header.pointee.ncmds {
                    guard remaining >= MemoryLayout<load_command>.size else { break }
                    let command = cursor.load(as: load_command.self)
                    let size = Int(command.cmdsize)
                    guard size >= MemoryLayout<load_command>.size, size <= remaining else { break }
                    if command.cmd == LC_UUID {
                        guard size >= MemoryLayout<uuid_command>.size else { break }
                        uuid = UUID(uuid: cursor.load(as: uuid_command.self).uuid).uuidString
                        break
                    }
                    cursor = cursor.advanced(by: size)
                    remaining -= size
                }
            }
            return NativeTouchImage(path: String(cString: name), address: String(UInt(bitPattern: header), radix: 16), uuid: uuid)
        }
    }

    static func installIfRequested(application: UIApplication) {
        let environment = ProcessInfo.processInfo.environment
        guard !installed,
              environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let requested = environment["TSK_TEST_NATIVE_TOUCH_TRACE"],
              requested == environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: requested) != nil,
              let token = environment["TSK_UI_TEST_SESSION"], UUID(uuidString: token) != nil,
              let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let observer = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.tsk_pr77_sendEvent(_:))),
              let alphaSetter = class_getInstanceMethod(UIView.self, #selector(setter: UIView.alpha)),
              let alphaObserver = class_getInstanceMethod(UIView.self, #selector(UIView.tsk_pr77_setAlpha(_:))),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        session = token
        replica = requested
        destination = directory.appendingPathComponent("participant-fixture-pr77-touch-\(token)-\(ProcessInfo.processInfo.processIdentifier).json")
        method_exchangeImplementations(original, observer)
        method_exchangeImplementations(alphaSetter, alphaObserver)
        installed = true
        append("installed", details: ["applicationClass": NSStringFromClass(type(of: application)), "originProbe": "weak-v1", "alphaProbe": "setter-v1"])
        DispatchQueue.main.async {
            images = loadedImages()
            append("alpha.images", details: ["count": String(images.count), "snapshotOutsideDispatch": "true"])
            exportAfterDispatch()
        }
        exportAfterDispatch()
    }

    static func parameterChanged(_ editing: TaskRowEditing, previous: TaskRowParameter?, current: TaskRowParameter?) {
        guard installed else { return }
        append("parameter.write", details: [
            "owner": identity(editing), "expandedOwner": expandedOwner ?? "nil", "rowID": editing.rowID,
            "previous": previous?.rawValue ?? "nil", "current": current?.rawValue ?? "nil"
        ])
        exportAfterDispatch()
    }

    static func expansionChanged(_ editing: TaskRowEditing, expanded: Bool) {
        guard installed else { return }
        let owner = identity(editing)
        if expanded { expandedOwner = owner; activeEditing = editing }
        else if expandedOwner == owner { expandedOwner = nil }
        append("row.expanded", details: ["owner": owner, "rowID": editing.rowID, "expanded": String(expanded)])
        exportAfterDispatch()
    }

    static func keyboardRegistrationWillApply(router: UUID, ordinal: Int, details: [String: String]) {
        guard installed else { return }
        keyboardApplyOrdinals[router.uuidString] = max(keyboardApplyOrdinals[router.uuidString] ?? 0, ordinal)
        append("keyboard-registration.apply", details: details.merging([
            "router": router.uuidString, "applyOrdinal": String(ordinal)
        ]) { _, current in current })
        exportAfterDispatch()
    }

    static func mainRebuildRequest(router: UUID, applyOrdinal: Int, requestOrdinal: Int, phase: String) {
        guard installed else { return }
        mainRebuildRequestOrdinals[router.uuidString] = max(mainRebuildRequestOrdinals[router.uuidString] ?? 0, requestOrdinal)
        append("main-rebuild.request." + phase, details: [
            "router": router.uuidString, "applyOrdinal": String(applyOrdinal),
            "requestOrdinal": String(requestOrdinal), "menuSystem": "main"
        ])
        exportAfterDispatch()
    }

    static func receive(_ event: UIEvent, stage: String) {
        guard installed, event.type == .touches else { return }
        lastEventStage = stage
        for touch in (event.allTouches ?? []).prefix(4) {
            guard touch.phase != .stationary else { continue }
            lastEventPhase = String(touch.phase.rawValue)
            let location = touch.location(in: touch.window)
            var ancestors: [[String: String]] = []
            var originAncestors: [UIView] = []
            var view = touch.view
            while let current = view, ancestors.count < 16 {
                if stage == "touch.before", touch.phase == .began { originAncestors.append(current) }
                ancestors.append([
                    "id": identity(current), "class": NSStringFromClass(type(of: current)),
                    "identifier": String((current.accessibilityIdentifier ?? "").prefix(160)),
                    "frame": NSCoder.string(for: current.frame), "bounds": NSCoder.string(for: current.bounds),
                    "windowFrame": NSCoder.string(for: current.convert(current.bounds, to: current.window)),
                    "window": current.window.map(identity) ?? "nil", "superview": current.superview.map(identity) ?? "nil",
                    "hidden": String(current.isHidden), "alpha": String(describing: current.alpha),
                    "interactionEnabled": String(current.isUserInteractionEnabled)
                ])
                view = current.superview
            }
            let touchID = ObjectIdentifier(touch)
            if stage == "touch.before", touch.phase == .began,
               touchOrigins[touchID]?.beganTimestamp != touch.timestamp {
                if touchOrigins.removeValue(forKey: touchID) != nil { droppedOriginCaptures += 1 }
                if touchOrigins.count < 4 {
                    let captureSequence = sequence + 1
                    if let control = originAncestors.first(where: { $0 is UIControl }) {
                        sourceCandidates.append(SourceCandidate(sequence: captureSequence, timestamp: touch.timestamp,
                                                                location: location, leaf: touch.view, control: control, window: touch.window))
                        sourceCandidates = Array(sourceCandidates.suffix(4))
                    }
                    touchOrigins[touchID] = TouchOrigin(sequence: captureSequence, timestamp: touch.timestamp,
                                                       location: location, ancestors: originAncestors, window: touch.window,
                                                       sources: sourceCandidates)
                    if let collection = originAncestors.compactMap({ $0 as? UICollectionView }).first,
                       originAncestors.contains(where: { $0 is UICollectionViewCell }) {
                        trackAlpha(collection, touch: identity(touch), sequence: captureSequence, generation: touch.timestamp)
                    }
                } else {
                    droppedOriginCaptures += 1
                }
            }
            originAncestors.removeAll()
            let origin = touchOrigins[touchID]
            let samplesBoundary = touch.phase == .began || touch.phase == .ended || touch.phase == .cancelled
            var originSamples = samplesBoundary ? origin?.samples() ?? [] : []
            if let origin, origin.isNewProject, samplesBoundary {
                originSamples += origin.sources.flatMap { $0.samples() }
            }
            let recognizers = (touch.gestureRecognizers ?? []).prefix(16).map { recognizer in
                [
                    "id": identity(recognizer), "class": NSStringFromClass(type(of: recognizer)),
                    "view": recognizer.view.map(identity) ?? "nil", "state": String(recognizer.state.rawValue),
                    "enabled": String(recognizer.isEnabled), "cancelsTouches": String(recognizer.cancelsTouchesInView),
                    "delaysBegan": String(recognizer.delaysTouchesBegan), "delaysEnded": String(recognizer.delaysTouchesEnded)
                ]
            }
            append(stage, details: [
                "event": identity(event), "eventTimestamp": String(event.timestamp),
                "touch": identity(touch), "touchTimestamp": String(touch.timestamp),
                "phase": String(touch.phase.rawValue), "type": String(touch.type.rawValue),
                "tapCount": String(touch.tapCount), "location": NSCoder.string(for: location),
                "view": touch.view.map(identity) ?? "nil", "window": touch.window.map(identity) ?? "nil",
                "keyboardApplyOrdinals": ordinalSignature(keyboardApplyOrdinals),
                "mainRebuildRequestOrdinals": ordinalSignature(mainRebuildRequestOrdinals),
                "ancestorLimitReached": String(view != nil),
                "recognizersTruncated": String((touch.gestureRecognizers?.count ?? 0) > 16),
                "originCaptureSequence": origin.map { String($0.captureSequence) } ?? "unavailable",
                "originBeganTimestamp": origin.map { String($0.beganTimestamp) } ?? "unavailable",
                "originDroppedCaptures": String(droppedOriginCaptures),
                "originTouchesTruncated": String((event.allTouches?.count ?? 0) > 4),
                "alphaMutationCount": String(alphaMutationCount), "alphaDroppedMutations": String(alphaDroppedMutations),
                "sourceCandidateSequences": origin?.sources.map { String($0.sequence) }.joined(separator: ",") ?? "unavailable",
                "sourceAssociation": origin?.sources.isEmpty == false ? "unverified-candidates" : "unavailable"
            ], ancestors: ancestors, recognizers: recognizers, origins: originSamples)
            if stage == "touch.after", touch.phase == .ended || touch.phase == .cancelled {
                touchOrigins.removeValue(forKey: touchID)
            }
        }
    }

    static func exportAfterDispatch() {
        guard installed, !exportPending, sequence != lastExportedSequence else { return }
        exportPending = true
        DispatchQueue.main.async {
            guard let destination else { return }
            let exportedSequence = sequence
            let packet = NativeTouchExport(schema: 1, session: session, replica: replica,
                                           processID: ProcessInfo.processInfo.processIdentifier,
                                           evictedRecords: evictedRecords, alphaMutationCount: alphaMutationCount,
                                           alphaDroppedMutations: alphaDroppedMutations, records: records, images: images)
            output.async {
                do {
                    var enriched = packet
                    enriched.symbols = symbolize(packet.records)
                    let data = try JSONEncoder().encode(enriched)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    NSLog("[PR77-TOUCH] Export failed: %@", String(describing: error))
                }
                DispatchQueue.main.async {
                    lastExportedSequence = exportedSequence
                    exportPending = false
                    exportAfterDispatch()
                }
            }
        }
    }

    private static func append(_ stage: String, details: [String: String], ancestors: [[String: String]] = [], recognizers: [[String: String]] = [], origins: [[String: String]] = []) {
        sequence += 1
        if records.count == 512 {
            records.removeFirst()
            evictedRecords += 1
        }
        records.append(NativeTouchRecord(sequence: sequence, stage: stage,
                                         uptime: ProcessInfo.processInfo.systemUptime, wallTime: Date().timeIntervalSince1970,
                                         details: details, ancestors: ancestors, recognizers: recognizers, origins: origins))
    }

    private static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    nonisolated private static func symbolize(_ records: [NativeTouchRecord]) -> [NativeTouchSymbol] {
        let addresses = Set(records.flatMap { $0.details["stack"]?.split(separator: ",").map(String.init) ?? [] })
        return addresses.sorted().compactMap { address in
            guard let number = UInt(address, radix: 16), let pointer = UnsafeRawPointer(bitPattern: number) else { return nil }
            var info = Dl_info()
            guard dladdr(pointer, &info) != 0 else {
                return NativeTouchSymbol(address: address, image: nil, imageAddress: nil, symbol: nil, symbolAddress: nil)
            }
            return NativeTouchSymbol(address: address, image: info.dli_fname.map { String(cString: $0) },
                                     imageAddress: info.dli_fbase.map { String(UInt(bitPattern: $0), radix: 16) },
                                     symbol: info.dli_sname.map { String(cString: $0) },
                                     symbolAddress: info.dli_saddr.map { String(UInt(bitPattern: $0), radix: 16) })
        }
    }

    private static func ordinalSignature(_ values: [String: Int]) -> String {
        values.sorted { $0.key < $1.key }.map { $0.key + ":" + String($0.value) }.joined(separator: ",")
    }

    @MainActor
    private final class WeakOriginView {
        weak var view: UIView?
        let captured: [String: String]

        init(_ role: String, _ view: UIView?) {
            self.view = view
            captured = [
                "role": role, "captured": String(view != nil), "capturedID": view.map(TaskNativeTouchDiagnostics.identity) ?? "nil",
                "capturedClass": view.map { NSStringFromClass(type(of: $0)) } ?? "nil",
                "capturedIdentifier": String((view?.accessibilityIdentifier ?? "").prefix(160)),
                "capturedWindow": view?.window.map(TaskNativeTouchDiagnostics.identity) ?? "nil",
                "capturedSuperview": view?.superview.map(TaskNativeTouchDiagnostics.identity) ?? "nil",
                "capturedFrame": view.map { NSCoder.string(for: $0.convert($0.bounds, to: $0.window)) } ?? "unavailable"
            ]
        }

        func sample(in window: UIWindow?, point: CGPoint) -> [String: String] {
            guard let view else { return captured.merging(["alive": "false"]) { _, value in value } }
            var chain: [String] = []
            var ancestor: UIView? = view
            while let current = ancestor, chain.count < 16 {
                chain.append(TaskNativeTouchDiagnostics.identity(current))
                ancestor = current.superview
            }
            let frame = window.map { view.convert(view.bounds, to: $0) }
            var sample = captured
            sample["alive"] = "true"
            sample["currentWindow"] = view.window.map(TaskNativeTouchDiagnostics.identity) ?? "nil"
            sample["currentSuperview"] = view.superview.map(TaskNativeTouchDiagnostics.identity) ?? "nil"
            sample["currentIdentifier"] = String((view.accessibilityIdentifier ?? "").prefix(160))
            sample["originalWindowAvailable"] = String(window != nil)
            sample["sameOriginalWindow"] = String(window != nil && view.window === window)
            sample["currentFrameInOriginalWindow"] = frame.map { NSCoder.string(for: $0) } ?? "unavailable"
            sample["containsOriginalTouchPoint"] = frame.map { String($0.contains(point)) } ?? "unavailable"
            sample["hidden"] = String(view.isHidden)
            sample["alpha"] = String(describing: view.alpha)
            sample["interactionEnabled"] = String(view.isUserInteractionEnabled)
            sample["currentAncestorIDs"] = chain.joined(separator: ",")
            sample["currentAncestorsTruncated"] = String(ancestor != nil)
            return sample
        }
    }

    @MainActor
    private struct SourceCandidate {
        let sequence: Int
        let timestamp: TimeInterval
        let location: CGPoint
        let window: WeakOriginView
        let views: [WeakOriginView]

        init(sequence: Int, timestamp: TimeInterval, location: CGPoint, leaf: UIView?, control: UIView, window: UIWindow?) {
            self.sequence = sequence
            self.timestamp = timestamp
            self.location = location
            self.window = WeakOriginView("sourceWindow", window)
            var views = [WeakOriginView("sourceControl", control), WeakOriginView("sourceParent", control.superview)]
            if leaf !== control { views.append(WeakOriginView("sourceLeaf", leaf)) }
            self.views = views
        }

        func samples() -> [[String: String]] {
            views.map { $0.sample(in: window.view as? UIWindow, point: location).merging([
                "sourceCaptureSequence": String(sequence), "sourceBeganTimestamp": String(timestamp),
                "sourceLocation": NSCoder.string(for: location), "sourceAssociation": "candidate"
            ]) { _, value in value } }
        }
    }

    @MainActor
    private struct TouchOrigin {
        let captureSequence: Int
        let beganTimestamp: TimeInterval
        let location: CGPoint
        let views: [WeakOriginView]
        let originalIndexPath: IndexPath?
        let sources: [SourceCandidate]
        let isNewProject: Bool

        init(sequence: Int, timestamp: TimeInterval, location: CGPoint, ancestors: [UIView], window: UIWindow?, sources: [SourceCandidate]) {
            captureSequence = sequence
            beganTimestamp = timestamp
            self.location = location
            self.sources = sources
            let content = ancestors.first { $0.accessibilityIdentifier == "row-new-project" }
            let cell = ancestors.compactMap { $0 as? UICollectionViewCell }.first
            let collection = ancestors.compactMap { $0 as? UICollectionView }.first
            isNewProject = content != nil
            originalIndexPath = cell.flatMap { collection?.indexPath(for: $0) }
            views = [WeakOriginView("leaf", ancestors.first), WeakOriginView("optionContent", content),
                     WeakOriginView("cell", cell), WeakOriginView("collection", collection), WeakOriginView("window", window)]
        }

        func samples() -> [[String: String]] {
            let window = views[4].view as? UIWindow
            var samples = views.map { $0.sample(in: window, point: location) }
            samples[2]["originalIndexPath"] = originalIndexPath.map { String(describing: $0) } ?? "unavailable"
            if views[2].view != nil {
                samples[0]["descendsFromOriginalCell"] = String(samples[0]["currentAncestorIDs"]?.components(separatedBy: ",").contains(views[2].captured["capturedID"] ?? "nil") == true)
            }
            if let collection = views[3].view as? UICollectionView {
                if let cell = views[2].view as? UICollectionViewCell {
                    samples[2]["descendsFromOriginalCollection"] = String(samples[2]["currentAncestorIDs"]?.components(separatedBy: ",").contains(TaskNativeTouchDiagnostics.identity(collection)) == true)
                    samples[2]["currentIndexPathForOriginalCell"] = collection.indexPath(for: cell).map { String(describing: $0) } ?? "nil"
                }
                if let originalIndexPath {
                    samples[2]["currentCellAtOriginalIndexPath"] = collection.cellForItem(at: originalIndexPath).map(TaskNativeTouchDiagnostics.identity) ?? "nil"
                }
            }
            return samples
        }
    }
}

extension UIApplication {
    @objc dynamic func tsk_pr77_sendEvent(_ event: UIEvent) {
        TaskNativeTouchDiagnostics.receive(event, stage: "touch.before")
        tsk_pr77_sendEvent(event)
        TaskNativeTouchDiagnostics.receive(event, stage: "touch.after")
        TaskNativeTouchDiagnostics.exportAfterDispatch()
    }
}

extension UIView {
    @objc nonisolated dynamic func tsk_pr77_setAlpha(_ value: CGFloat) {
        guard Thread.isMainThread else {
            tsk_pr77_setAlpha(value)
            return
        }
        let mutation = MainActor.assumeIsolated {
            TaskNativeTouchDiagnostics.alphaWillChange(self, requested: value)
        }
        tsk_pr77_setAlpha(value)
        if let mutation {
            MainActor.assumeIsolated { TaskNativeTouchDiagnostics.alphaDidChange(self, mutation: mutation) }
        }
    }
}
#endif
