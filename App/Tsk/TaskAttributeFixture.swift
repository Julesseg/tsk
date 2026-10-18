#if DEBUG && targetEnvironment(simulator)
import Foundation
import TskCore

@MainActor
func installTaskAttributeFixture(in store: TaskStore) async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TSK_TEST_ATTRIBUTE_DEFINITIONS_FIXTURE"] == "1" else { return }
    guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
          let session = environment["TSK_UI_TEST_SESSION"], UUID(uuidString: session) != nil,
          let name = environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: name) != nil else { throw CocoaError(.coderInvalidValue) }
    let manager = store.manager
    guard try await manager.attributeDefinitions().isEmpty else { throw CocoaError(.coderInvalidValue) }
    let definitions = [
        TaskAttributeDefinition(name: "note", type: .string),
        TaskAttributeDefinition(name: "score", type: .numeric),
        TaskAttributeDefinition(name: "review", type: .date),
        TaskAttributeDefinition(name: "effort", type: .duration),
        TaskAttributeDefinition(name: "reference", type: .uuid)
    ]
    for definition in definitions {
        _ = try await manager.saveAttributeDefinition(name: definition.name.rawValue, type: definition.type)
    }
    try await store.loadAttributeDefinitions()
    guard store.attributeDefinitions == definitions.sorted(by: { $0.name < $1.name }) else { throw CocoaError(.coderInvalidValue) }
}
#endif
