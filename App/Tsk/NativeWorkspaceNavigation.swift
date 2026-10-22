import SwiftUI
import UIKit

struct NativeWorkspaceNavigation: UIViewControllerRepresentable {
    struct Item {
        let id: String
        let title: String
        let image: String
        let accessibilityIdentifier: String
        let select: () -> Void
    }

    struct Section {
        let id: String
        let title: String
        let items: [Item]
    }

    let favorites: [Item]
    let current: Item?
    let sections: [Section]
    let selection: String
    var content: AnyView
    let prefersSidebar: Bool
    let presentationChanged: (Bool) -> Void
    let settings: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        var configuration = self
        configuration.content = AnyView(content.environment(\.taskKeyboardRouter, context.environment.taskKeyboardRouter))
        controller.configure(configuration)
    }

    final class Controller: UITabBarController, UITabBarControllerDelegate, UITabBarController.Sidebar.Delegate {
        private var configuration: NativeWorkspaceNavigation?
        private var items: [String: Item] = [:]
        private var ownedTabs: [String: UITab] = [:]
        private var ownedGroups: [String: UITabGroup] = [:]
        private var hosts: [String: UIHostingController<AnyView>] = [:]
        private var configuring = false
        private var visible = false
        private weak var observedScene: UIWindowScene?
        private var geometryObservation: NSKeyValueObservation?
        private var observationGeneration = 0
        private var geometryGeneration = 0
        private var wasResizing = false
        private var restorationPending = false
        private var catalogSuspended = false

        override func viewDidLoad() {
            super.viewDidLoad()
            mode = .tabSidebar
            delegate = self
            sidebar.delegate = self
            sidebar.bottomBarView = SettingsBar { [weak self] in self?.configuration?.settings() }
            registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: Controller, _: UITraitCollection) in
                Task { @MainActor [weak controller] in controller?.completeAdaptation() }
            }
        }

        func configure(_ configuration: NativeWorkspaceNavigation) {
            loadViewIfNeeded()
            if wasResizing || view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing == true {
                restorationPending = true
                suspendCatalog()
            }
            configuring = true
            let previousPreference = self.configuration?.prefersSidebar
            self.configuration = configuration
            let allItems = configuration.favorites + configuration.sections.flatMap(\.items) + (configuration.current.map { [$0] } ?? [])
            items = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
            let fixed = Set(configuration.favorites.map(\.id) + (configuration.current.map { [$0.id] } ?? []))
            for item in allItems {
                let tab = ownedTab(item)
                tab.title = item.title
                tab.image = UIImage(systemName: item.image)
                tab.accessibilityIdentifier = item.accessibilityIdentifier
                tab.preferredPlacement = fixed.contains(item.id) ? .fixed : .sidebarOnly
            }
            for host in hosts.values { host.rootView = configuration.content }
            var roots = configuration.favorites.map(ownedTab)
            if let current = configuration.current { roots.append(ownedTab(current)) }
            let primaryRoots = roots
            for section in configuration.sections {
                let children = section.items.map(ownedTab)
                let group = ownedGroups[section.id] ?? UITabGroup(title: section.title, image: nil, identifier: section.id, children: []) { [weak self] _ in
                    self?.ownedHost(section.id) ?? UIViewController()
                }
                group.title = section.title
                group.preferredPlacement = .sidebarOnly
                group.sidebarAppearance = .rootSection
                if group.children != children { group.children = children }
                ownedGroups[section.id] = group
                roots.append(group)
            }
            let selected = ownedTabs[configuration.selection]
            let canSelect = !wasResizing && view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing != true
            if canSelect, let selected, selected.tabBarController === self, selectedTab !== selected { selectedTab = selected }
            let displayedRoots = catalogSuspended || traitCollection.horizontalSizeClass == .compact ? primaryRoots : roots
            if tabs != displayedRoots { tabs = displayedRoots }
            let compact = configuration.favorites.map(\.id) + (configuration.current.map { [$0.id] } ?? [])
            if compactTabIdentifiers != compact { compactTabIdentifiers = compact }
            if canSelect, let selected, selectedTab !== selected { selectedTab = selected }
            let validItems = Set(allItems.map(\.id))
            let validGroups = Set(configuration.sections.map(\.id))
            ownedTabs = ownedTabs.filter { validItems.contains($0.key) }
            hosts = hosts.filter { validItems.contains($0.key) || validGroups.contains($0.key) }
            ownedGroups = ownedGroups.filter { validGroups.contains($0.key) }
            if previousPreference != configuration.prefersSidebar {
                restorationPending = true
                restorePresentationIfNeeded()
            }
            configuring = false
        }

        private func ownedTab(_ item: Item) -> UITab {
            if let tab = ownedTabs[item.id] { return tab }
            let tab = UITab(title: item.title, image: UIImage(systemName: item.image), identifier: item.id) { [weak self] _ in
                self?.ownedHost(item.id) ?? UIViewController()
            }
            ownedTabs[item.id] = tab
            return tab
        }

        private func ownedHost(_ id: String) -> UIHostingController<AnyView> {
            if let host = hosts[id] { return host }
            let host = UIHostingController(rootView: configuration?.content ?? AnyView(EmptyView()))
            hosts[id] = host
            return host
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            guard !configuring, let item = items[selectedTab.identifier] else { return }
            Task { @MainActor in item.select() }
        }

        func tabBarController(_ tabBarController: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar, animator: any UITabBarController.Sidebar.Animating) {
            let scene = view.window?.windowScene
            let identity = scene.map(ObjectIdentifier.init)
            let generation = observationGeneration
            let suppressed = configuring || restorationPending || scene?.effectiveGeometry.isInteractivelyResizing != false
            animator.addCompletion { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, !suppressed, visible, observationGeneration == generation,
                          let scene = view.window?.windowScene, identity == ObjectIdentifier(scene),
                          !scene.effectiveGeometry.isInteractivelyResizing, !restorationPending,
                          traitCollection.horizontalSizeClass == .regular else { return }
                    configuration?.presentationChanged(!self.sidebar.isHidden)
                }
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            visible = true
            observeScene()
            restorationPending = true
            if wasResizing || traitCollection.horizontalSizeClass == .compact { suspendCatalog() }
            completeAdaptation()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            visible = false
            observationGeneration += 1
            geometryObservation?.invalidate()
            geometryObservation = nil
            observedScene = nil
            wasResizing = false
            restorationPending = false
        }

        private func observeScene() {
            guard let scene = view.window?.windowScene, observedScene !== scene else { return }
            geometryObservation?.invalidate()
            observationGeneration += 1
            let generation = observationGeneration
            let identity = ObjectIdentifier(scene)
            observedScene = scene
            wasResizing = scene.effectiveGeometry.isInteractivelyResizing
            if wasResizing { restorationPending = true }
            geometryObservation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, change in
                guard let geometry = change.newValue else { return }
                let resizing = geometry.isInteractivelyResizing
                Task { @MainActor [weak self] in
                    guard let self, visible, observationGeneration == generation,
                          view.window?.windowScene.map(ObjectIdentifier.init) == identity else { return }
                    geometryGeneration += 1
                    wasResizing = resizing
                    if resizing {
                        restorationPending = true
                        suspendCatalog()
                    } else { completeAdaptation() }
                }
            }
        }

        // UIKit can otherwise select a sidebar group outside the compact root collection.
        override func willTransition(to newCollection: UITraitCollection, with coordinator: any UIViewControllerTransitionCoordinator) {
            if traitCollection.horizontalSizeClass != newCollection.horizontalSizeClass {
                restorationPending = true
                if newCollection.horizontalSizeClass == .compact { suspendCatalog() }
            }
            super.willTransition(to: newCollection, with: coordinator)
        }

        private func suspendCatalog() {
            guard !catalogSuspended else { return }
            catalogSuspended = true
            guard let configuration else { return }
            let previouslyConfiguring = configuring
            configuring = true
            if let desired = ownedTabs[configuration.selection], desired.tabBarController === self, selectedTab !== desired {
                selectedTab = desired
            }
            let primary = configuration.favorites.map(\.id) + (configuration.current.map { [$0.id] } ?? [])
            let roots = primary.compactMap { ownedTabs[$0] }
            if tabs != roots { tabs = roots }
            configuring = previouslyConfiguring
        }

        private func completeAdaptation() {
            let observation = observationGeneration
            let geometry = geometryGeneration
            let complete = { [weak self] in
                guard let self, visible, observationGeneration == observation, geometryGeneration == geometry,
                      !wasResizing, view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing == false else { return }
                if traitCollection.horizontalSizeClass == .regular, catalogSuspended, let configuration {
                    catalogSuspended = false
                    configure(configuration)
                }
                restoreSelectionIfNeeded()
                restorePresentationIfNeeded()
            }
            if let coordinator = transitionCoordinator,
               coordinator.animate(alongsideTransition: nil, completion: { _ in complete() }) { return }
            complete()
        }

        private func restoreSelectionIfNeeded() {
            guard visible, !wasResizing, view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing == false,
                  let configuration, let desired = ownedTabs[configuration.selection], desired.tabBarController === self,
                  selectedTab !== desired else { return }
            selectedTab = desired
        }

        private func restorePresentationIfNeeded() {
            guard visible, restorationPending, !wasResizing,
                  view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing == false,
                  traitCollection.horizontalSizeClass == .regular, let configuration else { return }
            let hidden = !configuration.prefersSidebar
            if sidebar.isHidden != hidden { sidebar.isHidden = hidden }
            let observation = observationGeneration
            let geometry = geometryGeneration
            Task { @MainActor [weak self] in
                guard let self, visible, observationGeneration == observation, geometryGeneration == geometry,
                      !wasResizing, view.window?.windowScene?.effectiveGeometry.isInteractivelyResizing == false,
                      traitCollection.horizontalSizeClass == .regular else { return }
                restorationPending = false
            }
        }
    }
}

private final class SettingsBar: UIView {
    init(action: @escaping () -> Void) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Settings"
        configuration.image = UIImage(systemName: "gearshape")
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "sidebar-settings"
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: SettingsBar, _: UITraitCollection) in
            Task { @MainActor [weak view] in view?.invalidateIntrinsicContentSize() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIFont.preferredFont(forTextStyle: .body).lineHeight + 32)
    }
}
