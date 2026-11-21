#if DEBUG
import SwiftUI
import UIKit

struct PlannerFrameProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private var link: CADisplayLink?
        private var previous: CFTimeInterval?
        private var intervals: [Int] = []

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
            guard window != nil else { return }
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
            get { ([Int(((previous ?? 0) * 1000).rounded())] + intervals).map(String.init).joined(separator: " ") }
            set {}
        }
    }
}
#endif
