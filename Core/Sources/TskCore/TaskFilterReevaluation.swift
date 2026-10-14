import Foundation

extension FilterExpression {
    func nextEvaluation(context: TaskFilterContext) -> Date? {
        switch self {
        case .all: return nil
        case .not(let expression): return expression.nextEvaluation(context: context)
        case .and(let left, let right), .or(let left, let right), .xor(let left, let right):
            return [left.nextEvaluation(context: context), right.nextEvaluation(context: context)].compactMap { $0 }.min()
        case .predicate(let predicate):
            switch predicate {
            case .date(let date):
                return date.operand.nextEvaluation(context: context)
            case .virtualTag(let tag, _): return tag.nextEvaluation(context: context)
            case .comparison(let name, _, _) where name == "status": return FilterVirtualTag.waiting.nextEvaluation(context: context)
            default: return nil
            }
        }
    }
}

extension FilterVirtualTag {
    func nextEvaluation(context: TaskFilterContext) -> Date? {
        switch self {
        case .waiting, .pending:
            return context.tasks.compactMap { FilterDateExpression.storedDate($0.attributes["wait"]) }.filter { $0 > context.now }.min()
        case .ready:
            let waits = context.tasks.compactMap { FilterDateExpression.storedDate($0.attributes["wait"]) }.filter { $0 > context.now }
            let schedules = context.tasks.compactMap { FilterDateExpression.storedDate($0.attributes["scheduled"]) }.filter { $0 >= context.now }.map { $0.addingTimeInterval(1) }
            return (waits + schedules).min()
        case .overdue:
            return context.tasks.compactMap { FilterDateExpression.storedDate($0.attributes["due"]) }.filter { $0 >= context.now }.map { $0.addingTimeInterval(1) }.min()
        case .due, .dueToday, .today, .yesterday, .tomorrow, .week, .month, .quarter, .year:
            return context.calendar.date(byAdding: .day, value: 1, to: context.calendar.startOfDay(for: context.now))
        default: return nil
        }
    }
}
