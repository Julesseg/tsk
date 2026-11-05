import SwiftUI
import UIKit

struct CaptureTabAction: UIViewRepresentable {
    let capture: () -> Void

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.capture = capture
        view.install()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        view.uninstall()
    }

    final class Anchor: UIView, UITabBarControllerDelegate {
        var capture: (() -> Void)?
        private weak var installedController: UITabBarController?
        private weak var forwardedDelegate: (any UITabBarControllerDelegate)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { uninstall() }
            else { install() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            install()
        }

        func install() {
            guard window != nil else { return }
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = (current as? UIViewController)?.tabBarController {
                    guard controller.delegate !== self else { return }
                    if let previous = controller.delegate as? Anchor { previous.uninstall() }
                    installedController = controller
                    forwardedDelegate = controller.delegate
                    controller.delegate = self
                    return
                }
                responder = current.next
            }
        }

        func uninstall() {
            if let controller = installedController, controller.delegate === self {
                controller.delegate = forwardedDelegate
            }
            installedController = nil
            forwardedDelegate = nil
        }

        func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            if tab === controller.tabs.last {
                capture?()
                return false
            }
            return forwardedDelegate?.tabBarController?(controller, shouldSelectTab: tab) ?? true
        }

        func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if viewController === controller.viewControllers?.last {
                capture?()
                return false
            }
            return forwardedDelegate?.tabBarController?(controller, shouldSelect: viewController) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || forwardedDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if forwardedDelegate?.responds(to: selector) == true { return forwardedDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}
