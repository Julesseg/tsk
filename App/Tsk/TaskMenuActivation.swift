import SwiftUI
import UIKit

struct TaskMenuActivation: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.activate = { _, _ in action() }
        view.refresh()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        coordinator.detach()
        coordinator.activate = nil
        view.coordinator = nil
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        private var deferredAttachment = false

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            refresh()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            deferredAttachment = false
            refresh()
        }

        func refresh() {
            coordinator?.attach(to: self)
            guard window != nil, !deferredAttachment else { return }
            deferredAttachment = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                coordinator?.attach(to: self)
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var activate: ((UIControl, Int) -> Void)?
        private weak var control: UIControl?
        private weak var anchor: Anchor?
        private var generation = 0

        func attach(to anchor: Anchor) {
            self.anchor = anchor
            var current = anchor.superview
            var candidate: UIControl?
            var ancestry: [String] = []
            while let view = current, ancestry.count < 16, let window = anchor.window, view.window === window {
                ancestry.append(String(describing: ObjectIdentifier(view)))
                if let source = view as? UIControl { candidate = source; break }
                if view === window { break }
                current = view.superview
            }
            if control !== candidate {
                detach()
                self.anchor = anchor
                control = candidate
                generation += 1
                candidate?.addTarget(self, action: #selector(menuActivated(_:)), for: .menuActionTriggered)
            }
        }

        func detach() {
            guard let control else { return }
            control.removeTarget(self, action: #selector(menuActivated(_:)), for: .menuActionTriggered)
            self.control = nil
        }

        @objc private func menuActivated(_ sender: UIControl) {
            let valid = sender === control && anchor?.window != nil && sender.window === anchor?.window
                && anchor?.isDescendant(of: sender) == true
            guard valid else { return }
            activate?(sender, generation)
        }
    }
}
