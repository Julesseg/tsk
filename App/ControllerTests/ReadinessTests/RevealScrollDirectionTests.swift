import Testing

@Suite struct TaskRevealScrollDirectionProof {
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
