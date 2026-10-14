import Foundation
import TskCore

extension TaskStore {
    var recurringTemplates: [TaskRecord] { allTasks.filter { $0.recurrenceInspection?.kind == .template } }

    func createRecurringTemplate(_ draft: RecurringTaskDraft) async -> TaskRecord? {
        await perform { try await $0.createRecurringTemplate(draft) }
    }
}
