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
        #expect(action?.appFrame == accepted.appFrame)
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

    @Test func waiterFailureCannotActOnAcceptedGeometry() {
        let attempt = TaskControlReadinessAttempt(now: { 0 }, sample: { sample() })
        #expect(attempt.evaluate())
        var performed = false
        #expect(!attempt.finish(waitCompleted: false) { _ in performed = true })
        #expect(!performed)
        #expect(attempt.failureReason == .waiterIncomplete)
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
