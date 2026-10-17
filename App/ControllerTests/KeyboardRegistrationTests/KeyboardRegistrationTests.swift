import Foundation
import Testing

@Suite struct TaskKeyboardRegistrationProof {
    final class Host {}
    let save = TaskKeyboardDeclaration(id: "save", input: "\r", modifiers: 1_048_576, title: "Save")

    @Test func unchangedDeclarationsAndLiveHostsDoNotRepeatNativeMutations() {
        let registration = TaskKeyboardRegistration(), host = Host()
        var mutations = 0
        for _ in 0..<20 { registration.reconcile([save], hosts: [host]) { mutations += 1 } }
        #expect(mutations == 1)
    }

    @Test func distinctHostChangesInvalidateButDuplicatesAndHostOrderDoNot() {
        let registration = TaskKeyboardRegistration(), first = Host(), second = Host()
        var mutations = 0
        for hosts in [[first], [first, first], [second, first, first], [first, second], [second], [first], [], []] {
            registration.reconcile([save], hosts: hosts) { mutations += 1 }
        }
        #expect(mutations == 5)
    }

    @Test func everyDeclarationFieldAndCommandOrderInvalidate() {
        let variants = [
            TaskKeyboardDeclaration(id: "edit", input: "\r", modifiers: 1_048_576, title: "Save"),
            TaskKeyboardDeclaration(id: "save", input: "n", modifiers: 1_048_576, title: "Save"),
            TaskKeyboardDeclaration(id: "save", input: "\r", modifiers: 1_179_648, title: "Save"),
            TaskKeyboardDeclaration(id: "save", input: "\r", modifiers: 1_048_576, title: nil),
            TaskKeyboardDeclaration(id: "save", input: "\r", modifiers: 1_048_576, title: "")
        ]
        let host = Host()
        for variant in variants {
            let registration = TaskKeyboardRegistration()
            var mutations = 0
            for declarations in [[save], [variant], [variant], [save, variant], [variant, save], [save]] {
                registration.reconcile(declarations, hosts: [host]) { mutations += 1 }
            }
            #expect(mutations == 5)
        }
        let registration = TaskKeyboardRegistration()
        var mutations = 0
        for declaration in [variants[3], variants[4]] {
            registration.reconcile([declaration], hosts: [host]) { mutations += 1 }
        }
        #expect(mutations == 2)
    }

    @Test func registrationDoesNotRetainHostsAndDeadOwnershipInvalidates() {
        let registration = TaskKeyboardRegistration()
        var host: Host? = Host()
        weak var weakHost = host
        var mutations = 0
        registration.reconcile([save], hosts: [host!]) { mutations += 1 }
        host = nil
        #expect(weakHost == nil)
        registration.reconcile([save], hosts: []) { mutations += 1 }
        registration.reconcile([save], hosts: []) { mutations += 1 }
        #expect(mutations == 2)
    }

    @Test func emptyCommandAndHostTransitionsApplyOnceEach() {
        let registration = TaskKeyboardRegistration(), host = Host()
        var mutations = 0
        registration.reconcile([], hosts: []) { mutations += 1 }
        registration.reconcile([], hosts: []) { mutations += 1 }
        registration.reconcile([save], hosts: [host]) { mutations += 1 }
        registration.reconcile([], hosts: [host]) { mutations += 1 }
        registration.reconcile([], hosts: [host]) { mutations += 1 }
        registration.reconcile([], hosts: []) { mutations += 1 }
        #expect(mutations == 4)
    }
}
