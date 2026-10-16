import Foundation
import CoreGraphics
import Testing

@Suite struct TaskControlReadinessProof {
    final class Clock { var now = 0.0 }
    let appFrame = CGRect(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 400, height: 800))
    func sample(enabled: Bool = true, hittable: Bool = true, frame: CGRect? = nil) -> TaskControlReadinessSample {
        TaskControlReadinessSample(exists: true, enabled: enabled, hittable: hittable,
                                   elementFrame: frame ?? CGRect(origin: CGPoint(x: 40, y: 70), size: CGSize(width: 80, height: 30)), appFrame: appFrame)
    }

    @Test func readySlowSnapshotActsBeforeTheWaitersFirstPollDelay() {
        let clock = Clock()
        var actions = 0
        var waits = 0
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
            clock.now += 3.986889958
            return sample()
        })
        let completed = attempt.waitUntilReady { _, evaluate in
            waits += 1
            clock.now += 1.027159625
            return evaluate()
        }
        let performed = attempt.finish(waitCompleted: completed) { _ in actions += 1 }
        #expect(performed)
        #expect(actions == 1)
        #expect(waits == 0)
        #expect(clock.now == 3.986889958)
        #expect(!attempt.finish(waitCompleted: completed) { _ in actions += 1 })
        #expect(actions == 1)
    }

    @Test func initiallyUnreadyControlWaitsOnlyForTheRemainingBudget() {
        let clock = Clock()
        var reads = 0
        var actions = 0
        var waitBudget: TimeInterval?
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
            reads += 1
            clock.now += 1
            return sample(enabled: reads > 1)
        })
        let completed = attempt.waitUntilReady { timeout, evaluate in
            waitBudget = timeout
            clock.now += 1
            return evaluate()
        }
        #expect(waitBudget == 4)
        #expect(completed)
        #expect(attempt.finish(waitCompleted: completed) { _ in actions += 1 })
        #expect(actions == 1)
        #expect(clock.now == 3)
    }

    @Test func expiredInitialSampleNeverWaitsOrDispatches() {
        for duration in [5.0, 5.2] {
            let clock = Clock()
            var waits = 0
            var actions = 0
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
                clock.now += duration
                return sample()
            })
            let completed = attempt.waitUntilReady { _, evaluate in
                waits += 1
                return evaluate()
            }
            #expect(!completed)
            #expect(waits == 0)
            #expect(!attempt.finish(waitCompleted: completed) { _ in actions += 1 })
            #expect(actions == 0)
            #expect(attempt.failureReason == .deadlineExpired)
        }
    }

    @Test func transientDisabledAndUnhittableControlGetsOnlyOneFullyReadyAction() {
        let clock = Clock()
        var current = sample(enabled: false)
        var actions: [TaskControlReadinessGeometry] = []
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        #expect(!attempt.evaluate())
        clock.now = 1; current = sample(hittable: false)
        #expect(!attempt.evaluate())
        clock.now = 2; current = sample()
        #expect(attempt.evaluate())
        #expect(actions.isEmpty)
        #expect(attempt.finish(waitCompleted: true) { actions.append($0) })
        #expect(actions.count == 1)
        #expect(!attempt.finish(waitCompleted: true) { actions.append($0) })
        #expect(actions.count == 1)
    }

    @Test func actionUsesOnlyTheAcceptedContainedGeometryPair() {
        let clock = Clock()
        var current = sample(frame: CGRect(origin: CGPoint(x: 400, y: 70), size: CGSize(width: 80, height: 30)))
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        #expect(!attempt.evaluate())
        clock.now = 1
        current = sample(frame: CGRect(origin: CGPoint(x: 70, y: 90), size: CGSize(width: 90, height: 40)))
        #expect(attempt.evaluate())
        let accepted = current
        current = sample(frame: CGRect(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 0, height: 0)))
        var action: TaskControlReadinessGeometry?
        #expect(attempt.finish(waitCompleted: true) { action = $0 })
        #expect(action?.elementFrame == accepted.elementFrame)
        #expect(action?.containmentFrame == accepted.appFrame)
    }

    @Test func emptyApplicationFrameUsesObservedContainingWindowForOneAction() {
        let clock = Clock()
        let controlFrame = CGRect(x: 40, y: 801.3333333333334, width: 360, height: 22)
        let windowFrame = CGRect(x: 0, y: 0, width: 440, height: 956)
        let current = TaskControlReadinessSample(exists: true, enabled: true, hittable: true,
                                                 elementFrame: controlFrame, appFrame: .zero,
                                                 appWindowFrames: [windowFrame])
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        #expect(attempt.evaluate())
        var actions: [TaskControlReadinessGeometry] = []
        #expect(attempt.finish(waitCompleted: true) { actions.append($0) })
        #expect(actions.count == 1)
        #expect(actions.first?.elementFrame == controlFrame)
        #expect(actions.first?.containmentFrame == windowFrame)
        #expect(!attempt.finish(waitCompleted: true) { actions.append($0) })
        #expect(actions.count == 1)
    }

    @Test func windowFallbackNeverBypassesReadinessOrKnownApplicationBounds() {
        let controlFrame = CGRect(x: 40, y: 801.3333333333334, width: 360, height: 22)
        let windowFrame = CGRect(x: 0, y: 0, width: 440, height: 956)
        let valid = TaskControlReadinessSample(exists: true, enabled: true, hittable: true,
                                               elementFrame: controlFrame, appFrame: .zero,
                                               appWindowFrames: [windowFrame])
        var noWindow = valid; noWindow.appWindowFrames = []
        var emptyWindow = valid; emptyWindow.appWindowFrames = [.zero]
        var unboundedWindow = valid; unboundedWindow.appWindowFrames = [.infinite]
        var outsideWindow = valid; outsideWindow.appWindowFrames = [CGRect(x: 0, y: 0, width: 440, height: 800)]
        var outsideApplication = valid; outsideApplication.appFrame = CGRect(x: 0, y: 0, width: 440, height: 800)
        var disabled = valid; disabled.enabled = false
        var unhittable = valid; unhittable.hittable = false
        var emptyControl = valid; emptyControl.elementFrame = .zero
        let missing = TaskControlReadinessSample(exists: false, appFrame: .zero, appWindowFrames: [windowFrame])
        for current in [noWindow, emptyWindow, unboundedWindow, outsideWindow, outsideApplication, disabled, unhittable, emptyControl, missing] {
            var performed = false
            let attempt = TaskControlReadinessAttempt(now: { 0 }, sample: { current })
            #expect(!attempt.evaluate())
            #expect(!attempt.finish(waitCompleted: true) { _ in performed = true })
            #expect(!performed)
        }
    }

    @Test func laterUnreadyObservationInvalidatesAnEarlierReadySample() {
        let clock = Clock()
        var current = sample()
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        #expect(attempt.evaluate())
        current = sample(hittable: false); clock.now = 1
        #expect(!attempt.evaluate())
        var performed = false
        #expect(!attempt.finish(waitCompleted: true) { _ in performed = true })
        #expect(!performed)
    }

    @Test func deadlineBeforeSamplingAfterSamplingAndBeforeActionSuppressesActions() {
        for phase in 0..<3 {
            let clock = Clock()
            var reads = 0
            var performed = false
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
                reads += 1
                if phase == 1 { clock.now = 5 }
                return sample()
            })
            if phase == 0 { clock.now = 5 }
            #expect(attempt.evaluate() == (phase == 2))
            clock.now = 5
            #expect(!attempt.finish(waitCompleted: true) { _ in performed = true })
            #expect(!performed)
            #expect(reads == (phase == 0 ? 0 : 1))
            #expect(attempt.failureReason == .deadlineExpired)
        }
    }

    @Test func expiredSamplingKeepsItsReasonAndElapsedBeforeFailureAttachments() {
        let clock = Clock()
        var performed = false
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
            clock.now = 5.2
            return sample()
        })
        #expect(!attempt.evaluate())
        #expect(!attempt.finish(waitCompleted: false) { _ in performed = true })
        clock.now = 8
        #expect(!performed)
        #expect(attempt.failureReason == .deadlineExpired)
        #expect(attempt.diagnostic.contains("elapsed=5.2 "))
        #expect(attempt.diagnostic.contains("sampleStartedElapsed=0.0 "))
        #expect(attempt.diagnostic.contains("sampleElapsed=5.2 "))
    }

    @Test func waiterFailureCannotActOnAcceptedGeometry() {
        let attempt = TaskControlReadinessAttempt(now: { 0 }, sample: { sample() })
        #expect(attempt.evaluate())
        var performed = false
        #expect(!attempt.finish(waitCompleted: false) { _ in performed = true })
        #expect(!performed)
        #expect(attempt.failureReason == .waiterIncomplete)
    }

    @Test func nativeSnapshotFailureKeepsUnknownPresenceAndCannotAct() {
        let current = TaskControlReadinessSample(exists: nil, snapshotError: "Native snapshot unavailable")
        var performed = false
        let attempt = TaskControlReadinessAttempt(now: { 0 }, sample: { current })
        #expect(!attempt.evaluate())
        #expect(!attempt.finish(waitCompleted: true) { _ in performed = true })
        #expect(!performed)
        #expect(attempt.failureReason == .snapshotFailed)
        #expect(attempt.diagnostic.contains("exists=null"))
    }

    @Test func overBudgetUnhittableSampleRemainsUnhittableInDiagnostics() {
        let clock = Clock()
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
            clock.now = 6
            return sample(hittable: false)
        })
        #expect(!attempt.evaluate())
        #expect(!attempt.finish(waitCompleted: false) { _ in Issue.record("An unhittable control must not act") })
        #expect(attempt.failureReason == .deadlineExpired)
        #expect(attempt.diagnostic.contains("sampleElapsed=6.0 "))
        #expect(attempt.diagnostic.contains("sampleReason=unhittable"))
    }

    @Test func failedSamplesKeepActualReasonsAndUnknownFieldsDistinct() {
        let absent = TaskControlReadinessSample(exists: false)
        #expect(absent.failureReason == .missing)
        #expect(absent.enabled == nil)
        #expect(absent.hittable == nil)
        #expect(absent.diagnostic.contains("enabled=null"))
        #expect(sample(enabled: false).failureReason == .disabled)
        #expect(sample(hittable: false).failureReason == .unhittable)
        #expect(sample(frame: CGRect(origin: CGPoint(x: 40, y: 70), size: CGSize(width: 0, height: 30))).failureReason == .nonpositiveFrame)
        #expect(sample(frame: CGRect(origin: CGPoint(x: 400, y: 70), size: CGSize(width: 80, height: 30))).failureReason == .outsideApp)
        let nonfinite = TaskControlReadinessSample(exists: true, enabled: true, hittable: true,
                                                  elementFrame: CGRect(origin: CGPoint(x: CGFloat.infinity, y: 70), size: CGSize(width: 80, height: 30)), appFrame: appFrame)
        #expect(nonfinite.diagnostic.contains("inf"))
    }
}
