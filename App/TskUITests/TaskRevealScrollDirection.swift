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
    private let visibleFrame: CGRect
    let top: CGFloat
    let bottom: CGFloat

    init(visibleFrame: CGRect, top: CGFloat, keyboardFrame: CGRect?, bottomInsetFrame: CGRect?, tabBarFrame: CGRect? = nil) {
        self.visibleFrame = visibleFrame
        self.top = top
        let obstructionTop = [keyboardFrame, bottomInsetFrame, tabBarFrame].compactMap { $0 }.filter { $0.intersects(visibleFrame) }.map { $0.minY }.min()
        bottom = min(visibleFrame.maxY - 16, obstructionTop.map { $0 - 8 } ?? visibleFrame.maxY - 16)
    }

    static func lowerInsetFrame(_ candidate: CGRect?, in visibleFrame: CGRect) -> CGRect? {
        guard let candidate, candidate.intersects(visibleFrame), candidate.minY >= visibleFrame.midY else { return nil }
        return candidate
    }

    func contains(midY: CGFloat) -> Bool { midY >= top && midY <= bottom }

    func contains(frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite &&
            frame.width > 0 && frame.height > 0 && frame.minX >= visibleFrame.minX &&
            frame.maxX <= visibleFrame.maxX && frame.minY >= top && frame.maxY <= bottom
    }

    func scrollTargetY(for frame: CGRect, requireFullVisibility: Bool) -> CGFloat {
        requireFullVisibility && frame.maxY > bottom ? frame.maxY : frame.midY
    }
}
