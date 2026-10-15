import Foundation

struct TaskKeyboardDeclaration: Equatable {
    let id: String
    let input: String
    let modifiers: Int
    let title: String?
}

final class TaskKeyboardRegistration {
    private var declarations: [TaskKeyboardDeclaration]?
    private var hosts: [ObjectIdentifier: WeakHost] = [:]

    func reconcile(_ declarations: [TaskKeyboardDeclaration], hosts: [AnyObject], apply: () -> Void) {
        let current = Dictionary(hosts.map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { first, _ in first })
        let sameHosts = current.count == self.hosts.count && current.allSatisfy { self.hosts[$0.key]?.value === $0.value }
        guard self.declarations != declarations || !sameHosts else { return }
        apply()
        self.declarations = declarations
        self.hosts = current.mapValues(WeakHost.init)
    }

    private final class WeakHost {
        weak var value: AnyObject?
        init(_ value: AnyObject) { self.value = value }
    }
}
