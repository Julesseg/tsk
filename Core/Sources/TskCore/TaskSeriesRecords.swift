import Foundation

struct TaskSeriesRecords {
    let template: TaskRecord
    let children: [TaskRecord]
    let affected: [TaskRecord]

    init(records: [TaskRecord], id: UUID, cutoff: Date) throws {
        guard let template = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
        guard template.status == "recurring", template.attributes["parent"] == nil else { throw TaskManagementError.unsupportedTaskKind }
        let children = records.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == id }
        let mask = template.attributes["mask"].map { Array($0.utf8) }
        if let mask, !mask.allSatisfy({ [45, 87, 43, 88].contains($0) }) { throw TaskSeriesMetadataError.invalidSeries }
        var positions = Set<Int>()
        var affected: [TaskRecord] = []
        for child in children {
            guard let index = child.occurrenceIndex,
                  let mask, index < mask.count, positions.insert(index).inserted else { throw TaskSeriesMetadataError.invalidSeries }
            switch child.status {
            case "pending":
                guard [45, 87].contains(mask[index]), let due = child.deadline else { throw TaskSeriesMetadataError.invalidSeries }
                if due >= cutoff { affected.append(child) }
            case "completed": guard mask[index] == 43 else { throw TaskSeriesMetadataError.invalidSeries }
            case "deleted": guard mask[index] == 88 else { throw TaskSeriesMetadataError.invalidSeries }
            default: throw TaskSeriesMetadataError.invalidSeries
            }
        }
        self.template = template
        self.children = children
        self.affected = affected.sorted { ($0.deadline ?? .distantFuture, $0.id.uuidString) < ($1.deadline ?? .distantFuture, $1.id.uuidString) }
    }
}
