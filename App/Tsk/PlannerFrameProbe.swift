#if DEBUG
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct PlannerFrameProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private var link: CADisplayLink?
        private var previous: CFTimeInterval?
        private var intervals: [Int] = []
        private let touches = TouchIntervals()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "planner-frame-probe"
            accessibilityLabel = "Planner frame intervals"
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            previous = nil
            touches.view?.removeGestureRecognizer(touches)
            guard let window else { return }
            window.addGestureRecognizer(touches)
            let display = CADisplayLink(target: self, selector: #selector(sample))
            display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            display.add(to: .main, forMode: .common)
            link = display
        }

        @objc private func sample(_ display: CADisplayLink) {
            if let previous {
                let gap = display.timestamp - previous
                if gap > 0.025 {
                    intervals.append(Int((display.timestamp * 1000).rounded()))
                    intervals.append(Int((gap * 1000).rounded()))
                }
            }
            previous = display.timestamp
        }

        override var accessibilityValue: String? {
            get {
                let frames = [Int(((previous ?? 0) * 1000).rounded())] + intervals
                return frames.map(String.init).joined(separator: " ") + "|" + touches.intervals.map(String.init).joined(separator: " ")
            }
            set {}
        }
    }

    private final class TouchIntervals: UIGestureRecognizer {
        private var start: TimeInterval?
        private(set) var intervals: [Int] = []

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
        }

        override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if start == nil { start = touches.first?.timestamp }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            if let start, let end = touches.first?.timestamp {
                intervals += [Int((start * 1000).rounded()), Int((end * 1000).rounded())]
            }
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
        override func reset() { super.reset(); start = nil }
    }

}
#endif
