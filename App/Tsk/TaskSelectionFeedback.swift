import SwiftUI

struct TaskSelectionRowFeedback: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(selected ? (colorScheme == .dark ? 0.26 : 0.13) : 0))
                    .scaleEffect(x: selected ? 1 : 0, anchor: .leading)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
    }
}
