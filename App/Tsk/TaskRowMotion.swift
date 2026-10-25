import Foundation
import QuartzCore

@MainActor
final class TaskRowMotion: NSObject {
    private let duration: TimeInterval
    private let update: (Double) -> Void
    private var displayLink: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private var start: TimeInterval?

    init(duration: TimeInterval, update: @escaping (Double) -> Void) {
        self.duration = duration
        self.update = update
        super.init()
    }

    func run() async {
        guard !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let link = CADisplayLink(target: self, selector: #selector(step(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                displayLink = link
                link.add(to: .main, forMode: .common)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        let completion = continuation
        continuation = nil
        completion?.resume()
    }

    @objc private func step(_ link: CADisplayLink) {
        let start = self.start ?? link.timestamp
        self.start = start
        let fraction = min(1, max(0, (link.targetTimestamp - start) / duration))
        update(1 - pow(1 - fraction, 4))
        if fraction == 1 { cancel() }
    }
}
