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
