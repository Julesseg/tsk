import Foundation
import CoreGraphics

enum TaskControlReadinessPolicy {
    static let accessibilityAdmissionTimeout: TimeInterval = 20
}

enum TaskControlReadinessFailure: String {
    case missing, disabled, unhittable, unsampled, snapshotFailed, nonpositiveFrame, outsideApp
    case deadlineExpired, waiterIncomplete, alreadyFinished
    case keyboardUnavailable, keyboardCoveringControl, changingKeyboardLayout
}

struct TaskControlReadinessGeometry {
    let elementFrame: CGRect
    let containmentFrame: CGRect
}

struct TaskNativeMenuOptionGeometry: Equatable {
    let frame: CGRect
    let ancestorFrames: [CGRect]

    func visibleInApplication(_ applicationFrame: CGRect, windowFrames: [CGRect]) -> Self? {
        var frames = ancestorFrames
        if applicationFrame.isEmpty, frames.first == applicationFrame {
            guard let window = windowFrames.first(where: { !$0.isEmpty && !$0.isInfinite && $0.contains(frame) }) else { return nil }
            frames[0] = window
        }
        let candidate = Self(frame: frame, ancestorFrames: frames)
        return candidate.isVisible ? candidate : nil
    }

    var isVisible: Bool {
        func valid(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite && frame.width > 0 && frame.height > 0
        }
        return valid(frame) && !ancestorFrames.isEmpty && ancestorFrames.allSatisfy { valid($0) && $0.contains(frame) }
    }
}

struct TaskControlReadinessSample {
    var exists: Bool?
    var enabled: Bool?
    var hittable: Bool?
    var elementFrame: CGRect?
    var appFrame: CGRect?
    var appWindowFrames: [CGRect] = []
    var snapshotError: String?
    var keyboardFrames: [CGRect]?

    var containmentFrame: CGRect? {
        guard let appFrame, appFrame.isEmpty, let elementFrame else { return appFrame }
        return appWindowFrames.first { !$0.isEmpty && !$0.isInfinite && $0.contains(elementFrame) } ?? appFrame
    }

    var failureReason: TaskControlReadinessFailure? {
        guard snapshotError == nil else { return .snapshotFailed }
        guard let exists else { return .unsampled }
        guard exists else { return .missing }
        guard let enabled else { return .unsampled }
        guard enabled else { return .disabled }
        guard let hittable else { return .unsampled }
        guard hittable else { return .unhittable }
        guard let elementFrame, let containmentFrame else { return .unsampled }
        guard elementFrame.width > 0, elementFrame.height > 0 else { return .nonpositiveFrame }
        guard containmentFrame.contains(elementFrame) else { return .outsideApp }
        if let keyboardFrames {
            guard let keyboard = keyboardFrames.first, !keyboard.isEmpty, !keyboard.isInfinite,
                  keyboard.intersects(containmentFrame) else { return .keyboardUnavailable }
            let visible = keyboardFrames.filter { !$0.isEmpty && !$0.isInfinite && $0.intersects(containmentFrame) }
            guard !visible.contains(where: { $0.intersects(elementFrame) }) else { return .keyboardCoveringControl }
        }
        return nil
    }

    var diagnostic: String {
        func value<T>(_ field: T?) -> String { field.map { String(describing: $0) } ?? "null" }
        let contained = elementFrame.flatMap { frame in containmentFrame.map { $0.contains(frame) } }
        return "exists=\(value(exists)) snapshotError=\(value(snapshotError)) enabled=\(value(enabled)) hittable=\(value(hittable)) elementFrame=\(value(elementFrame)) appFrame=\(value(appFrame)) appWindowFrames=\(appWindowFrames) keyboardFrames=\(value(keyboardFrames)) containmentFrame=\(value(containmentFrame)) positiveWidth=\(value(elementFrame.map { $0.width > 0 })) positiveHeight=\(value(elementFrame.map { $0.height > 0 })) contained=\(value(contained)) sampleReason=\(failureReason?.rawValue ?? "ready")"
    }
}

final class TaskControlReadinessAttempt {
    private let now: () -> TimeInterval
    private let beforeSample: ((TimeInterval) -> Void)?
    private let sample: () -> TaskControlReadinessSample
    private let started: TimeInterval
    private let deadline: TimeInterval
    private var accepted: TaskControlReadinessGeometry?
    private var finished = false
    private var finishedAt: TimeInterval?
    private var lastSample: TaskControlReadinessSample?
    private var sampleCount = 0
    private var sampleStartedElapsed: TimeInterval?
    private var sampleElapsed: TimeInterval?
    private var previousKeyboardGeometry: [CGRect]?
    private(set) var failureReason: TaskControlReadinessFailure? = .unsampled

    init(now: @escaping () -> TimeInterval, deadline: TimeInterval? = nil, beforeSample: ((TimeInterval) -> Void)? = nil, sample: @escaping () -> TaskControlReadinessSample) {
        self.now = now
        self.beforeSample = beforeSample
        self.sample = sample
        started = now()
        self.deadline = min(started + TaskControlReadinessPolicy.accessibilityAdmissionTimeout, deadline ?? .infinity)
    }

    var remainingTime: TimeInterval { max(0, deadline - now()) }
    var diagnostic: String {
        "elapsed=\((finishedAt ?? now()) - started) samples=\(sampleCount) sampleStartedElapsed=\(sampleStartedElapsed.map(String.init(describing:)) ?? "null") sampleElapsed=\(sampleElapsed.map(String.init(describing:)) ?? "null") deadlineExpired=\((finishedAt ?? now()) >= deadline) reason=\(failureReason?.rawValue ?? "ready") \(lastSample?.diagnostic ?? "sample=null")"
    }

    func waitUntilReady(wait: (TimeInterval, @escaping () -> Bool) -> Bool) -> Bool {
        if evaluate() { return true }
        guard remainingTime > 0 else { return false }
        return wait(remainingTime, evaluate)
    }

    func evaluate() -> Bool {
        guard !finished else { return false }
        accepted = nil
        let sampleStarted = now()
        guard sampleStarted < deadline else { failureReason = .deadlineExpired; return false }
        if let beforeSample {
            beforeSample(deadline)
            let preparedAt = now()
            guard preparedAt < deadline else {
                sampleStartedElapsed = sampleStarted - started
                sampleElapsed = preparedAt - sampleStarted
                failureReason = .deadlineExpired
                return false
            }
        }
        let current = sample()
        let sampleCompleted = now()
        sampleStartedElapsed = sampleStarted - started
        sampleElapsed = sampleCompleted - sampleStarted
        lastSample = current
        sampleCount += 1
        guard sampleCompleted < deadline else { failureReason = .deadlineExpired; return false }
        failureReason = current.failureReason
        if failureReason != nil { previousKeyboardGeometry = nil }
        if failureReason == nil, let frame = current.elementFrame, let containmentFrame = current.containmentFrame {
            if let keyboardFrames = current.keyboardFrames {
                let geometry = [frame, containmentFrame] + keyboardFrames
                let stable = previousKeyboardGeometry == geometry
                previousKeyboardGeometry = geometry
                guard stable else { failureReason = .changingKeyboardLayout; return false }
            }
            accepted = TaskControlReadinessGeometry(elementFrame: frame, containmentFrame: containmentFrame)
        }
        return accepted != nil
    }

    func finish(waitCompleted: Bool, perform: (TaskControlReadinessGeometry) -> Void) -> Bool {
        guard !finished else { failureReason = .alreadyFinished; return false }
        finished = true
        let completedAt = now()
        finishedAt = completedAt
        guard completedAt < deadline else { failureReason = .deadlineExpired; accepted = nil; return false }
        guard waitCompleted else { failureReason = .waiterIncomplete; accepted = nil; return false }
        guard let accepted else { return false }
        perform(accepted)
        self.accepted = nil
        return true
    }
}

enum TaskSwitchValue {
    static func matches(_ value: Any?, enabled: Bool) -> Bool {
        if let text = value as? String { return text == (enabled ? "1" : "0") }
        if let number = value as? NSNumber { return number == NSNumber(value: enabled) }
        return false
    }
}
