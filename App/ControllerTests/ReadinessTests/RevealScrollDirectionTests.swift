import CoreGraphics
import Testing

@Suite struct TaskRevealScrollDirectionProof {
    @Test func observedDependencyButtonMustClearForegroundTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 440, height: 956)
        let button = CGRect(x: 20, y: 888.7, width: 400, height: 52)
        let tabBar = CGRect(x: 0, y: 873, width: 440, height: 83)
        let body = TaskRevealVisibleBody(visibleFrame: visible, top: 124, keyboardFrame: nil, bottomInsetFrame: nil, tabBarFrame: tabBar)
        #expect(body.bottom == 865)
        #expect(!body.contains(midY: button.midY))
        var direction = TaskRevealScrollDirection(initialScrollUp: false)
        let scrollUp = direction.update(targetMidY: button.midY, bottom: body.bottom)
        #expect(scrollUp)
        #expect(body.contains(frame: button.offsetBy(dx: 0, dy: -250)))
        let modal = CGRect(x: 0, y: 72, width: 440, height: 720)
        #expect(TaskRevealVisibleBody.lowerInsetFrame(tabBar, in: modal) == nil)
        let keyboard = CGRect(x: 0, y: 653, width: 440, height: 245)
        let inset = CGRect(x: 0, y: 620, width: 440, height: 36)
        let editing = TaskRevealVisibleBody(visibleFrame: visible, top: 124, keyboardFrame: keyboard, bottomInsetFrame: inset, tabBarFrame: tabBar)
        #expect(editing.bottom == 612)
    }

    @Test func observedAppsRowMustClearFloatingSettingsSearchBeforeActivation() {
        let visible = CGRect(x: 0, y: 0, width: 440, height: 956)
        let apps = CGRect(x: 20, y: 833.666667, width: 400, height: 52)
        let search = CGRect(x: 28, y: 890, width: 384, height: 28)
        let lowerSearch = TaskRevealVisibleBody.lowerInsetFrame(search, in: visible)
        #expect(lowerSearch == search)
        #expect(TaskRevealVisibleBody.lowerInsetFrame(CGRect(x: 20, y: 100, width: 400, height: 48), in: visible) == nil)
        #expect(TaskRevealVisibleBody.lowerInsetFrame(CGRect(x: 450, y: 890, width: 100, height: 28), in: visible) == nil)
        let body = TaskRevealVisibleBody(visibleFrame: visible, top: 124, keyboardFrame: nil, bottomInsetFrame: lowerSearch)
        #expect(body.bottom == 882)
        #expect(body.contains(midY: apps.midY))
        #expect(!body.contains(frame: apps))
        var direction = TaskRevealScrollDirection(initialScrollUp: false)
        let scrollUp = direction.update(targetMidY: body.scrollTargetY(for: apps, requireFullVisibility: true), bottom: body.bottom)
        #expect(scrollUp)
        let shifted = apps.offsetBy(dx: 0, dy: -250)
        #expect(body.contains(frame: shifted))
        #expect(shifted.maxY < 880)
        var legacy = TaskRevealScrollDirection(initialScrollUp: true)
        let legacyScrollUp = legacy.update(targetMidY: body.scrollTargetY(for: apps, requireFullVisibility: false), bottom: body.bottom)
        #expect(!legacyScrollUp)
    }

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
