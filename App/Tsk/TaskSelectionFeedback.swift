import SwiftUI

struct TaskSelectionSwipe: Equatable {
    let rowID: String
    let translation: CGFloat
}

struct TaskSelectionRowFeedback: ViewModifier {
    let rowID: String
    let selected: Bool
    let swipe: TaskSelectionSwipe?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var active: Bool { swipe?.rowID == rowID }
    private var displacement: CGFloat {
        guard !reduceMotion, active, let swipe else { return 0 }
        let distance = max(0, swipe.translation)
        return 56 * distance / (distance + 60)
    }

    func body(content: Content) -> some View {
        let settle: Animation? = reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.15)
        content
            .offset(x: displacement)
            .animation(active ? nil : settle, value: displacement)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(selected ? (colorScheme == .dark ? 0.26 : 0.13) : 0))
                        .scaleEffect(x: selected ? 1 : 0, anchor: .leading)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: displacement)
                        .animation(active ? nil : settle, value: displacement)
                }
                .padding(.vertical, 2)
                .allowsHitTesting(false)
            }
    }
}
