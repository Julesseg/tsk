import CoreGraphics
import Testing

@Suite struct TaskRevealScrollDirectionProof {
    @Test func observedDismissalBandExcludesProjectAboveTheKeyboardAndRequiresScrolling() {
        let visible = CGRect(x: 0, y: 72, width: 440, height: 884)
        let project = CGRect(x: 40, y: 561.666687, width: 360, height: 22)
        let keyboard = CGRect(x: 0, y: 653, width: 440, height: 245)
        let dismissalBand = CGRect(x: 0, y: 572.666687, width: 440, height: 36.333313)
        let body = TaskRevealVisibleBody(visibleFrame: visible, top: 154, keyboardFrame: keyboard, bottomInsetFrame: dismissalBand)
        #expect(!body.contains(midY: project.midY))
        var direction = TaskRevealScrollDirection(initialScrollUp: false)
        let scrollUp = direction.update(targetMidY: project.midY, bottom: body.bottom)
        #expect(scrollUp)
        #expect(body.contains(midY: 463))
    }

    @Test func missingTargetDoesNotReverseTheCallerDirectionHalfwayThroughTheBudget() {
        for initialScrollUp in [true, false] {
            var direction = TaskRevealScrollDirection(initialScrollUp: initialScrollUp)
            for _ in 0..<14 {
                #expect(direction.update(targetMidY: nil, bottom: 820) == initialScrollUp)
            }
        }
    }

    @Test func observedTargetAboveRedirectsUpwardSearchAndMissingSamplesKeepThatDirection() {
        var direction = TaskRevealScrollDirection(initialScrollUp: true)
        for _ in 0..<8 { _ = direction.update(targetMidY: nil, bottom: 820) }
        let observedAbove = direction.update(targetMidY: 180, bottom: 820)
        let subsequentlyMissing = direction.update(targetMidY: nil, bottom: 820)
        #expect(!observedAbove)
        #expect(!subsequentlyMissing)
    }

    @Test func observedTargetBelowRedirectsDownwardSearchAndMissingSamplesKeepThatDirection() {
        var direction = TaskRevealScrollDirection(initialScrollUp: false)
        let observedBelow = direction.update(targetMidY: 1200, bottom: 820)
        #expect(observedBelow)
        for _ in 0..<14 {
            let subsequentlyMissing = direction.update(targetMidY: nil, bottom: 820)
            #expect(subsequentlyMissing)
        }
    }
}
