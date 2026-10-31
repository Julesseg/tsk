import Foundation
import CoreGraphics
import Testing

@Suite struct TaskRowControlIdentityProof {
    @Test func exactTaskAndUpcomingAppearancesRetainTheirFullUUIDAndContext() {
        let id = "A0000000-0000-0000-0000-000000000001"
        for prefix in ["task-", "upcoming-planned-1792144800-", "upcoming-deadline-1792144800-", "upcoming-planned--123-"] {
            #expect(TaskRowControlIdentity(prefix + id)?.rawValue == prefix + id)
        }
        #expect(TaskRowControlIdentity("upcoming-planned-1792144800-" + id) != TaskRowControlIdentity("upcoming-deadline-1792144800-" + id))
    }

    @Test func partialUUIDsOtherControlsAndMalformedAppearanceIdentitiesCannotBindARow() {
        let id = "A0000000-0000-0000-0000-000000000001"
        for value in [id, "task-" + id.dropLast(), "complete-task-row-" + id, "task-row-information", "upcoming-planned-unknown-" + id, "upcoming-other-1792144800-" + id, "prefix-task-" + id] {
            #expect(TaskRowControlIdentity(value) == nil)
        }
    }
}

@Suite struct TaskControlReadinessProof {
    final class Clock { var now = 0.0 }
    let appFrame = CGRect(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 400, height: 800))
    func sample(enabled: Bool = true, hittable: Bool = true, frame: CGRect? = nil) -> TaskControlReadinessSample {
        TaskControlReadinessSample(exists: true, enabled: enabled, hittable: hittable,
                                   elementFrame: frame ?? CGRect(origin: CGPoint(x: 40, y: 70), size: CGSize(width: 80, height: 30)), appFrame: appFrame)
    }

    @Test func observedAccessibilityLatencyStillAdmitsOneReadyAction() {
        for duration in [6.259, 8.749, 11.964] {
            let clock = Clock()
            var reads = 0
            var actions = 0
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: {
                reads += 1
                clock.now += duration
                return sample()
            })
            let completed = attempt.waitUntilReady { _, _ in
                Issue.record("An already ready sample must not require another poll")
                return false
            }
            #expect(completed)
            #expect(attempt.finish(waitCompleted: completed) { _ in actions += 1 })
            #expect(reads == 1)
            #expect(actions == 1)
            #expect(!attempt.finish(waitCompleted: completed) { _ in actions += 1 })
            #expect(actions == 1)
        }
    }

    @Test func explicitFiveSecondDeadlineStillRejectsObservedSlowReadySample() {
        let clock = Clock()
        var actions = 0
        var waits = 0
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: 5, sample: {
            clock.now += 8.749
            return sample()
        })
        let completed = attempt.waitUntilReady { _, _ in
            waits += 1
            return true
        }
        #expect(!completed)
        #expect(!attempt.finish(waitCompleted: completed) { _ in actions += 1 })
        #expect(!attempt.finish(waitCompleted: true) { _ in actions += 1 })
        #expect(actions == 0)
        #expect(waits == 0)
    }

    @Test func enclosingDeadlineBoundsPreparationSamplingAndDispatch() {
        for phase in 0..<3 {
            let clock = Clock()
            clock.now = 2
            var preparations = 0
            var samples = 0
            var actions = 0
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: 3, beforeSample: { deadline in
                preparations += 1
                #expect(deadline == 3)
            }, sample: {
                samples += 1
                if phase == 1 { clock.now = 3 }
                return sample()
            })
            #expect(attempt.remainingTime == 1)
            if phase == 0 { clock.now = 3 }
            #expect(attempt.evaluate() == (phase == 2))
            clock.now = 3
            #expect(!attempt.finish(waitCompleted: true) { _ in actions += 1 })
            #expect(actions == 0)
            #expect(preparations == (phase == 0 ? 0 : 1))
            #expect(samples == (phase == 0 ? 0 : 1))
            #expect(attempt.failureReason == .deadlineExpired)
        }
    }

    @Test func enclosingDeadlineNeverExtendsDefaultTwentySeconds() {
        for deadline in [nil, 100.0] as [TimeInterval?] {
            let clock = Clock()
            clock.now = 2
            var samples = 0
            var actions = 0
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: deadline, sample: {
                samples += 1
                return sample()
            })
            #expect(attempt.remainingTime == 20)
            clock.now = 22
            #expect(!attempt.evaluate())
            #expect(!attempt.finish(waitCompleted: true) { _ in actions += 1 })
            #expect(samples == 0)
            #expect(actions == 0)
        }
    }

    @Test func lateInterruptionIsHandledBeforeResamplingWithinTheOriginalDeadline() {
        let clock = Clock()
        var blocked = true
        var deadlines: [TimeInterval] = []
        var actions = 0
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, beforeSample: { deadline in
            deadlines.append(deadline)
            if clock.now >= 2 { blocked = false; clock.now += 1 }
        }, sample: {
            clock.now += 0.25
            return sample(hittable: !blocked)
        })
        #expect(!attempt.evaluate())
        clock.now = 2
        #expect(attempt.evaluate())
        #expect(attempt.finish(waitCompleted: true) { _ in actions += 1 })
        #expect(actions == 1)
        #expect(deadlines == [20, 20])
        #expect(clock.now == 3.25)
        #expect(!attempt.finish(waitCompleted: true) { _ in actions += 1 })
        #expect(actions == 1)
    }

    @Test func interruptionHandlingCannotResetOrOverrunTheReadinessDeadline() {
        for completedAt in [5.0, 5.2] {
            let clock = Clock()
            var preparations = 0
            var samples = 0
            var actions = 0
            let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: 5, beforeSample: { _ in
                preparations += 1
                clock.now = completedAt
            }, sample: {
                samples += 1
                return sample()
            })
            #expect(!attempt.evaluate())
            #expect(!attempt.evaluate())
            #expect(!attempt.finish(waitCompleted: true) { _ in actions += 1 })
            #expect(preparations == 1)
            #expect(samples == 0)
            #expect(actions == 0)
            #expect(attempt.failureReason == .deadlineExpired)
        }
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
        #expect(waitBudget == 19)
        #expect(completed)
        #expect(attempt.finish(waitCompleted: completed) { _ in actions += 1 })
        #expect(actions == 1)
        #expect(clock.now == 3)
    }

    @Test func expiredInitialSampleNeverWaitsOrDispatches() {
        for duration in [20.0, 20.2] {
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
                if phase == 1 { clock.now = 20 }
                return sample()
            })
            if phase == 0 { clock.now = 20 }
            #expect(attempt.evaluate() == (phase == 2))
            clock.now = 20
            #expect(!attempt.finish(waitCompleted: true) { _ in performed = true })
            #expect(!performed)
            #expect(reads == (phase == 0 ? 0 : 1))
            #expect(attempt.failureReason == .deadlineExpired)
        }
    }

    @Test func expiredSamplingKeepsItsReasonAndElapsedBeforeFailureAttachments() {
        let clock = Clock()
        var performed = false
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: 5, sample: {
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
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, deadline: 5, sample: {
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

    @Test func keyboardDismissalRejectsTheObservedPendingLayoutBeforeOneStableAction() {
        let clock = Clock()
        let screen = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let keyboard = CGRect(x: 0, y: 589, width: 1376, height: 440)
        var current = TaskControlReadinessSample(exists: true, enabled: true, hittable: true,
            elementFrame: CGRect(x: 818.5, y: 775, width: 143.5, height: 22.5), appFrame: screen, keyboardFrames: [])
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        #expect(!attempt.evaluate())
        #expect(attempt.failureReason == .keyboardUnavailable)
        current.keyboardFrames = [keyboard]
        clock.now = 1
        #expect(!attempt.evaluate())
        #expect(attempt.failureReason == .keyboardCoveringControl)
        current.elementFrame = CGRect(x: 818.5, y: 503.5, width: 143.5, height: 22.5)
        clock.now = 2
        #expect(!attempt.evaluate())
        #expect(attempt.failureReason == .changingKeyboardLayout)
        clock.now = 3
        #expect(attempt.evaluate())
        var actions = 0
        #expect(attempt.finish(waitCompleted: true) { _ in actions += 1 })
        #expect(actions == 1)
    }

    @Test func unavailableKeyboardAndInputAssistantCannotAdmitDismissal() {
        for frames in [[], [.zero], [.infinite], [CGRect(x: 0, y: 900, width: 400, height: 300)],
                       [CGRect(x: 0, y: 900, width: 400, height: 300), CGRect(x: 20, y: 530, width: 400, height: 300)],
                       [CGRect(x: 20, y: 530, width: 400, height: 300), CGRect(x: 20, y: 60, width: 400, height: 50)]] as [[CGRect]] {
            var current = sample()
            current.keyboardFrames = frames
            let attempt = TaskControlReadinessAttempt(now: { 0 }, sample: { current })
            #expect(!attempt.evaluate())
            #expect(!attempt.evaluate())
            #expect(!attempt.finish(waitCompleted: true) { _ in Issue.record("A missing or covering keyboard must not admit dismissal") })
        }
    }

    @Test func changingKeyboardLayoutCannotExtendTheOriginalDeadline() {
        let clock = Clock()
        var current = sample()
        current.keyboardFrames = [CGRect(x: 20, y: 530, width: 400, height: 300)]
        let attempt = TaskControlReadinessAttempt(now: { clock.now }, sample: { current })
        clock.now = 19
        #expect(!attempt.evaluate())
        clock.now = 20
        #expect(!attempt.evaluate())
        #expect(!attempt.finish(waitCompleted: true) { _ in Issue.record("Stable geometry after the deadline must not activate") })
        #expect(attempt.failureReason == .deadlineExpired)
    }
}

@Suite struct TaskSwitchValueProof {
    @Test func nativeBinaryRepresentationsMatchOnlyTheirExactState() {
        for value: Any in ["0", NSString(string: "0"), NSNumber(value: 0), NSNumber(value: false)] {
            #expect(TaskSwitchValue.matches(value, enabled: false))
            #expect(!TaskSwitchValue.matches(value, enabled: true))
        }
        for value: Any in ["1", NSString(string: "1"), NSNumber(value: 1), NSNumber(value: true)] {
            #expect(TaskSwitchValue.matches(value, enabled: true))
            #expect(!TaskSwitchValue.matches(value, enabled: false))
        }
        for value: Any? in [nil, "", "true", "1.0", NSNumber(value: -1), NSNumber(value: 2), NSNumber(value: 0.5)] {
            #expect(!TaskSwitchValue.matches(value, enabled: false))
            #expect(!TaskSwitchValue.matches(value, enabled: true))
        }
    }
}

@Suite struct TaskNativeMenuGeometryProof {
    @Test func editMenuUsesObservedWindowWhenTheApplicationRootHasNoFrame() {
        let window = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let menu = CGRect(x: 201, y: 273, width: 96.5, height: 44)
        let candidate = TaskNativeMenuOptionGeometry(frame: menu, ancestorFrames: [.zero, window, menu])
        #expect(candidate.visibleInApplication(.zero, windowFrames: [window])?.isVisible == true)
        #expect(candidate.visibleInApplication(.zero, windowFrames: []) == nil)
        #expect(candidate.visibleInApplication(.zero, windowFrames: [window.offsetBy(dx: 2000, dy: 0)]) == nil)
        let invalidParent = TaskNativeMenuOptionGeometry(frame: menu, ancestorFrames: [.zero, window, .zero, menu])
        #expect(invalidParent.visibleInApplication(.zero, windowFrames: [window]) == nil)
    }

    @Test func recordedPhoneAndPadMenuRowsAreInsideTheirVisiblePanels() {
        for (window, panel, collection, row) in [
            (CGRect(x: 0, y: 0, width: 440, height: 956), CGRect(x: 150, y: 354, width: 250, height: 188), CGRect(x: 150, y: 354, width: 250, height: 956), CGRect(x: 150, y: 406, width: 250, height: 42)),
            (CGRect(x: 0, y: 0, width: 1376, height: 1032), CGRect(x: 722, y: 468, width: 224, height: 168), CGRect(x: 722, y: 468, width: 224, height: 1032), CGRect(x: 722, y: 514, width: 224, height: 38)),
        ] {
            #expect(TaskNativeMenuOptionGeometry(frame: row, ancestorFrames: [window, panel, collection, row]).isVisible)
        }
    }

    @Test func oversizedCollectionBoundsCannotAdmitAClippedMenuRow() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let panel = CGRect(x: 722, y: 468, width: 224, height: 168)
        let collection = CGRect(x: 722, y: 468, width: 224, height: 1032)
        let hiddenRow = CGRect(x: 722, y: 640, width: 224, height: 38)
        #expect(collection.contains(hiddenRow))
        #expect(!TaskNativeMenuOptionGeometry(frame: hiddenRow, ancestorFrames: [window, panel, collection, hiddenRow]).isVisible)
    }

    @Test func missingInvalidAndOffWindowMenuGeometryIsRejected() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let row = CGRect(x: 722, y: 514, width: 224, height: 38)
        #expect(!TaskNativeMenuOptionGeometry(frame: row, ancestorFrames: []).isVisible)
        for invalid in [CGRect.zero, CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 224, height: 38)] {
            #expect(!TaskNativeMenuOptionGeometry(frame: invalid, ancestorFrames: [window]).isVisible)
            #expect(!TaskNativeMenuOptionGeometry(frame: row, ancestorFrames: [window, invalid]).isVisible)
        }
        #expect(!TaskNativeMenuOptionGeometry(frame: row.offsetBy(dx: 1376, dy: 0), ancestorFrames: [window]).isVisible)
    }
}
