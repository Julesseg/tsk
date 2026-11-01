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
        button.addAction(UIAction { [weak coordinator = context.coordinator, weak button] _ in
            PR77MenuLifecycle.record("menuAction.before", button: button)
            coordinator?.unfocus()
            PR77MenuLifecycle.record("menuAction.after", button: button)
        }, for: .menuActionTriggered)
        return button
    }

    func updateUIView(_ button: TaskRowMenuControl, context: Context) {
        if PR77MenuLifecycle.enabled { button.pr77UpdateCalls += 1 }
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
                         state: option == configuration.selection ? .on : .off) { [weak coordinator, weak button] _ in
                    PR77MenuLifecycle.record("choice.action", button: button, persist: true)
                    guard let coordinator, coordinator.isEnabled, coordinator.configuration == configuration else { return }
                    coordinator.select(option.rawValue)
                }
            }
            var children: [UIMenuElement] = [UIMenu(options: [.displayInline, .singleSelection], children: choices)]
            if parameter == .project {
                let newProject = UIAction(title: "New project…", image: UIImage(systemName: "folder.badge.plus")) { [weak coordinator, weak button] _ in
                    PR77MenuLifecycle.record("choice.action", button: button, persist: true)
                    guard let coordinator, coordinator.isEnabled, coordinator.configuration == configuration else { return }
                    coordinator.openPicker()
                }
                newProject.accessibilityIdentifier = "row-new-project"
                children.append(newProject)
            }
            button.menu = UIMenu(children: children)
            if PR77MenuLifecycle.enabled { button.pr77MenuAssignments += 1 }
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
            if PR77MenuLifecycle.enabled { button.pr77LabelAssignments += 1 }
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

    var pr77IntrinsicCalls = 0
    var pr77LayoutCalls = 0
    var pr77FrameChanges = 0
    var pr77SizeChanges = 0
    var pr77UpdateCalls = 0
    var pr77MenuAssignments = 0
    var pr77LabelAssignments = 0
    private var pr77LastSize = CGSize.zero
    private var pr77LastFrame = CGRect.zero

    init() {
        super.init(frame: .zero)
        PR77MenuLifecycle.install()
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.accessibilityElementsHidden = true
        addSubview(label)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        if PR77MenuLifecycle.enabled { pr77IntrinsicCalls += 1 }
        let size = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if PR77MenuLifecycle.enabled, size != pr77LastSize { pr77SizeChanges += 1; pr77LastSize = size }
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if PR77MenuLifecycle.enabled {
            pr77LayoutCalls += 1
            if frame != pr77LastFrame { pr77FrameChanges += 1; pr77LastFrame = frame }
        }
        let size = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        label.frame = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    override var isHighlighted: Bool {
        didSet { label.alpha = isHighlighted ? 0.65 : 1 }
    }

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        CGPoint(x: bounds.midX, y: label.frame.maxY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        PR77MenuLifecycle.record("window.changed", button: self)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        guard PR77MenuLifecycle.enabled else { return }
        PR77MenuLifecycle.record("willDisplay", button: self, details: ["hasAnimator": animator != nil, "configuration": PR77MenuLifecycle.identity(configuration)])
        animator?.addCompletion { [weak self] in PR77MenuLifecycle.record("display.completed", button: self) }
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        guard PR77MenuLifecycle.enabled else { return }
        PR77MenuLifecycle.record("willEnd", button: self, details: ["hasAnimator": animator != nil, "configuration": PR77MenuLifecycle.identity(configuration)])
        animator?.addCompletion { [weak self] in PR77MenuLifecycle.record("end.completed", button: self, persist: true) }
    }
}
