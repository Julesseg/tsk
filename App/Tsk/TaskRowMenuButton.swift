import SwiftUI
import TskCore

struct TaskRowMenuButton: UIViewRepresentable {
    let editing: TaskRowEditing
    let parameter: TaskRowParameter
    let projects: [String]
    let unfocus: () -> Void
    let openPicker: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    struct Configuration: Equatable {
        let owner: ObjectIdentifier
        let parameter: TaskRowParameter
        let selection: UTF8String
        let options: [UTF8String]
    }

    func makeUIView(context: Context) -> TaskRowMenuControl {
        let button = TaskRowMenuControl()
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.unfocus() }, for: .menuActionTriggered)
        return button
    }

    func updateUIView(_ button: TaskRowMenuControl, context: Context) {
        let coordinator = context.coordinator
        coordinator.isEnabled = isEnabled
        coordinator.unfocus = unfocus
        coordinator.openPicker = openPicker
        coordinator.select = { value in
            if parameter == .project { editing.draft.taskDraft.project = value }
            else { editing.draft.taskDraft.priority = value }
        }
        let selection = parameter == .project ? editing.draft.taskDraft.project : editing.draft.taskDraft.priority
        let options: [UTF8String]
        if parameter == .project {
            let named = (projects + [selection]).filter { !$0.isEmpty }.map { UTF8String($0) }
            options = [UTF8String("")] + Set(named).sorted()
        } else {
            let priorities = ["", "L", "M", "H"]
            options = (priorities + (priorities.contains(selection) ? [] : [selection])).map { UTF8String($0) }
        }
        let configuration = Configuration(owner: ObjectIdentifier(editing), parameter: parameter,
                                          selection: UTF8String(selection), options: options)
        let menuChanged = coordinator.configuration != configuration
        if menuChanged {
            let choices = options.map { option in
                UIAction(title: parameter == .project ? (option.rawValue.isEmpty ? "No project" : option.rawValue)
                            : TaskRowParameter.priorityTitle(option.rawValue),
                         state: option == configuration.selection ? .on : .off) { [weak coordinator] _ in
                    guard let coordinator, coordinator.isEnabled, coordinator.configuration == configuration else { return }
                    coordinator.select(option.rawValue)
                }
            }
            var children: [UIMenuElement] = [UIMenu(options: [.displayInline, .singleSelection], children: choices)]
            if parameter == .project {
                let newProject = UIAction(title: "New project…", image: UIImage(systemName: "folder.badge.plus")) { [weak coordinator] _ in
                    guard let coordinator, coordinator.isEnabled, coordinator.configuration == configuration else { return }
                    coordinator.openPicker()
                }
                newProject.accessibilityIdentifier = "row-new-project"
                children.append(newProject)
            }
            button.menu = UIMenu(children: children)
            coordinator.configuration = configuration
        }
        button.isEnabled = isEnabled
        button.accessibilityLabel = parameter.title
        button.accessibilityValue = parameter.value(in: editing.draft.taskDraft) ?? "Not set"
        button.accessibilityIdentifier = "row-" + parameter.identifier
        if menuChanged || coordinator.colorScheme != colorScheme || coordinator.dynamicTypeSize != dynamicTypeSize {
            let label = TaskRowParameterLabel(parameter: parameter, value: parameter.value(in: editing.draft.taskDraft))
                .modifier(TaskRowParameterPillAppearance())
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .fixedSize()
            button.label.configuration = UIHostingConfiguration { AnyView(label) }.margins(.all, 0)
            button.invalidateIntrinsicContentSize()
            coordinator.colorScheme = colorScheme
            coordinator.dynamicTypeSize = dynamicTypeSize
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isEnabled = true
        var configuration: Configuration?
        var colorScheme: ColorScheme?
        var dynamicTypeSize: DynamicTypeSize?
        var unfocus: () -> Void = {}
        var openPicker: () -> Void = {}
        var select: (String) -> Void = { _ in }
    }
}

final class TaskRowMenuControl: UIButton {
    let label = UIHostingConfiguration { AnyView(EmptyView()) }.margins(.all, 0).makeContentView()

    init() {
        super.init(frame: .zero)
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.accessibilityElementsHidden = true
        addSubview(label)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        let size = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        label.frame = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    override var isHighlighted: Bool {
        didSet { label.alpha = isHighlighted ? 0.65 : 1 }
    }

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        CGPoint(x: bounds.midX, y: label.frame.maxY)
    }
}
