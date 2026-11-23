import SwiftUI
import UIKit

struct TaskDayMonthGrid: UIViewRepresentable {
    @MainActor final class Cache {
        private var months: [Date] = []
        private var grids: [Date: Grid] = [:]

        func views(for dates: [Date]) -> [Grid] {
            if months != dates {
                grids = Dictionary(uniqueKeysWithValues: dates.map { ($0, grids[$0] ?? Grid()) })
                months = dates
            }
            return dates.compactMap { grids[$0] }
        }
    }

    let grid: Grid
    let month: Date
    let selected: Date
    let minimum: Date?
    let expanded: Bool
    let choose: (Date) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    func makeUIView(context: Context) -> Grid { grid }

    func updateUIView(_ grid: Grid, context: Context) {
        grid.choose = choose
        grid.accessibilityElementsHidden = !expanded
        grid.isUserInteractionEnabled = expanded
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return }
        grid.display(month: start, calendar: calendar, locale: locale, selected: selected, minimum: minimum, interactive: expanded)
    }

    static func dismantleUIView(_ grid: Grid, coordinator: ()) { grid.choose = nil }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Grid, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: uiView.gridHeight)
    }

    final class Grid: UIView {
        private var month: Date?
        private var calendar = Calendar.current
        private var locale = Locale.current
        private var selected: Date?
        private var minimum: Date?
        private var interactive = false
        private var selectedIndex: Int?
        private var padding = 0
        private var dates: [Date] = []
        private let weekdays = (0..<7).map { _ in UILabel() }
        private var buttons: [UIButton] = []
        private let highlight = UIView()
        var choose: ((Date) -> Void)?

        private var weekdayHeight: CGFloat { max(24, ceil(UIFont.preferredFont(forTextStyle: .caption1).lineHeight)) }
        private var rowHeight: CGFloat { max(40, ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight)) }
        var gridHeight: CGFloat { weekdayHeight + CGFloat((padding + dates.count + 6) / 7) * rowHeight }

        override init(frame: CGRect) {
            super.init(frame: frame)
            highlight.isUserInteractionEnabled = false
            addSubview(highlight)
            for label in weekdays {
                label.textAlignment = .center
                label.font = .preferredFont(forTextStyle: .caption1)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.isAccessibilityElement = false
                addSubview(label)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        func display(month: Date, calendar: Calendar, locale: Locale, selected: Date, minimum: Date?, interactive: Bool) {
            let changedMonth = self.month != month || self.calendar != calendar || self.locale != locale
            let changedInteraction = self.interactive != interactive
            guard changedMonth || self.selected != selected || self.minimum != minimum || changedInteraction else { return }
            if changedMonth {
                self.month = month
                self.calendar = calendar
                self.locale = locale
                let symbols = calendar.veryShortStandaloneWeekdaySymbols
                for (index, label) in weekdays.enumerated() { label.text = symbols[(calendar.firstWeekday - 1 + index) % 7] }
                padding = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
                let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
                dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }
                while buttons.count < dates.count {
                    let button = UIButton(type: .system)
                    button.tag = buttons.count
                    button.setTitleColor(.label, for: .normal)
                    button.setTitleColor(.tertiaryLabel, for: .disabled)
                    button.titleLabel?.adjustsFontForContentSizeCategory = true
                    button.addTarget(self, action: #selector(picked), for: .touchUpInside)
                    addSubview(button)
                    buttons.append(button)
                }
            }
            self.selected = selected
            self.minimum = minimum
            self.interactive = interactive
            selectedIndex = dates.firstIndex { calendar.isDate($0, inSameDayAs: selected) }
            let body = UIFont.preferredFont(forTextStyle: .body)
            let number = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day()
            let spoken = number.weekday(.wide).month(.wide).year()
            for (index, button) in buttons.enumerated() {
                button.isHidden = index >= dates.count
                guard !button.isHidden else { continue }
                let date = dates[index]
                if changedMonth {
                    button.setTitle(date.formatted(number), for: .normal)
                }
                if changedMonth || changedInteraction {
                    button.isAccessibilityElement = interactive
                    button.accessibilityLabel = interactive ? date.formatted(spoken) : nil
                    button.accessibilityIdentifier = interactive ? "planner-date-\(Int(date.timeIntervalSince1970))" : nil
                }
                let current = index == selectedIndex
                button.accessibilityTraits = current ? [.button, .selected] : .button
                button.titleLabel?.font = current ? .systemFont(ofSize: body.pointSize, weight: .semibold) : body
                button.isEnabled = minimum.map { date >= $0 } ?? true
            }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let width = bounds.width / 7
            let header = weekdayHeight
            let height = rowHeight
            func column(_ index: Int) -> CGFloat {
                CGFloat(effectiveUserInterfaceLayoutDirection == .rightToLeft ? 6 - index % 7 : index % 7) * width
            }
            for (index, label) in weekdays.enumerated() {
                label.frame = CGRect(x: column(index), y: 0, width: width, height: header)
            }
            for index in dates.indices {
                let slot = padding + index
                buttons[index].frame = CGRect(x: column(slot), y: header + CGFloat(slot / 7) * height, width: width, height: height)
            }
            highlight.isHidden = selectedIndex == nil
            if let selectedIndex {
                let frame = buttons[selectedIndex].frame
                let diameter = min(width, height)
                highlight.frame = CGRect(x: frame.midX - diameter / 2, y: frame.midY - diameter / 2, width: diameter, height: diameter)
                highlight.layer.cornerRadius = diameter / 2
                highlight.backgroundColor = tintColor.withAlphaComponent(0.2)
            }
        }

        @objc private func picked(_ sender: UIButton) { choose?(dates[sender.tag]) }
    }
}
