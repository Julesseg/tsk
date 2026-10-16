import CoreGraphics

struct TaskRevealScrollDirection {
    private var scrollUp: Bool

    init(initialScrollUp: Bool) {
        scrollUp = initialScrollUp
    }

    mutating func update(targetMidY: CGFloat?, bottom: CGFloat) -> Bool {
        if let targetMidY {
            scrollUp = targetMidY > bottom
        }
        return scrollUp
    }
}

struct TaskRevealVisibleBody {
    let top: CGFloat
    let bottom: CGFloat

    init(visibleFrame: CGRect, top: CGFloat, keyboardFrame: CGRect?, bottomInsetFrame: CGRect?) {
        self.top = top
        let obstructionTop = [keyboardFrame, bottomInsetFrame].compactMap { $0 }.filter { $0.intersects(visibleFrame) }.map { $0.minY }.min()
        bottom = min(visibleFrame.maxY - 16, obstructionTop.map { $0 - 8 } ?? visibleFrame.maxY - 16)
    }

    func contains(midY: CGFloat) -> Bool { midY >= top && midY <= bottom }
}
