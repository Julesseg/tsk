import Foundation

public extension TaskNotificationCenter {
    func delivered() async throws -> [TaskNotificationRequest] { [] }
    func addImmediate(_ request: TaskNotificationRequest) async throws { throw TaskManagementError.storage("Immediate notification delivery is unavailable in this adapter.") }
}

extension TaskManager {
    static func originalNotificationEvents(_ tasks: [TaskRecord]) -> [TaskNotificationEvent] {
        tasks.flatMap { task in
            [(TaskNotificationSource.planned, "scheduled"), (.due, "due")].compactMap { source, key in
                guard let raw = task.attributes[key], let seconds = Int64(raw), seconds >= 0, seconds <= 253402300799 else { return nil }
                return TaskNotificationEvent(taskID: task.id, source: source, storedSeconds: seconds)
            }
        }
    }

    func reconcileMissedNotifications(plan: TaskNotificationPlan, history: TaskSynchronizationHistory?, state: inout TaskNotificationState, locallyWritten: [TaskRecord], calendar: Calendar, center: any TaskNotificationCenter, store: any TaskNotificationStateStore, errors: inout [String]) async throws -> [TaskNotificationRequest] {
        if state.initialized != true {
            let baselineTasks: [TaskRecord]
            if let history { baselineTasks = history.baseline } else { baselineTasks = try await tasks() }
            for event in Self.originalNotificationEvents(baselineTasks) where !state.known.contains(event) { state.known.append(event) }
            state.initialized = true
        }
        for event in Self.originalNotificationEvents(locallyWritten) where !state.known.contains(event) { state.known.append(event) }
        var pending = state.pendingMissed ?? []
        if let success = history?.success, success.id != state.lastSuccessfulSynchronization {
            let received = try Self.notificationPlan(tasks: success.tasks, preferences: state.preferences, calendar: calendar, at: now())
            let accepted = Set(state.accepted.map(\.event))
            for request in received.past {
                let events = request.events.filter { !state.known.contains($0) && !accepted.contains($0) }
                if let candidate = request.replacingEvents(events), !pending.contains(candidate) { pending.append(candidate) }
            }
            for event in Self.originalNotificationEvents(success.tasks) where !state.known.contains(event) { state.known.append(event) }
            state.lastSuccessfulSynchronization = success.id
        }
        let eligible = Set((plan.past + plan.future).flatMap(\.events))
        let delivered = try await center.delivered()
        let evidence = delivered + (try await center.pending()).compactMap(\.request)
        var attempts = state.attemptingMissed ?? []
        for request in attempts {
            let confirmed = Set(evidence.flatMap(\.events))
            for event in request.events where confirmed.contains(event) && !state.accepted.contains(where: { $0.event == event }) {
                state.accepted.append(TaskNotificationAcceptance(event: event, effectiveDate: request.fireDate, acceptedAt: now(), immediate: true))
            }
        }
        let accepted = Set(state.accepted.map(\.event))
        attempts = attempts.compactMap { $0.replacingEvents($0.events.filter { eligible.contains($0) && !accepted.contains($0) }) }
        let uncertain = Set(attempts.flatMap(\.events))
        let queued = Set(pending.flatMap(\.events)).subtracting(accepted).subtracting(uncertain)
        pending = plan.past.compactMap { $0.replacingEvents($0.events.filter { queued.contains($0) }) }
        state.pendingMissed = pending
        state.attemptingMissed = attempts
        try await store.save(state)
        let retained = Set((pending + attempts).map(\.immediateIdentifier))
        await center.remove(identifiers: try await center.pending().filter { $0.identifier.hasPrefix(TaskNotificationRequest.missedIdentifierPrefix) && !retained.contains($0.identifier) }.map(\.identifier))
        var submitted: [TaskNotificationRequest] = []
        var retryable: [TaskNotificationRequest] = []
        var remaining = Set(pending.flatMap(\.events))
        while !remaining.isEmpty {
            guard try await center.authorization().permitsAlerts else { errors.append("Missed alerts need notification permission. Retry after enabling notifications."); break }
            let current = try await notificationPlan(preferences: state.preferences, calendar: calendar)
            let candidates = current.past.compactMap { $0.replacingEvents($0.events.filter { remaining.contains($0) }) }
            guard let request = candidates.first else {
                state.pendingMissed = retryable
                try await store.save(state)
                break
            }
            remaining = Set(candidates.flatMap(\.events)).subtracting(request.events)
            state.pendingMissed = retryable + candidates.dropFirst()
            state.attemptingMissed?.append(request)
            try await store.save(state)
            do {
                try await center.addImmediate(request)
            } catch {
                state.attemptingMissed?.removeAll { $0 == request }
                retryable.append(request)
                state.pendingMissed?.append(request)
                try await store.save(state)
                errors.append(error.localizedDescription)
                continue
            }
            for event in request.events { state.accepted.append(TaskNotificationAcceptance(event: event, effectiveDate: request.fireDate, acceptedAt: now(), immediate: true)) }
            state.attemptingMissed?.removeAll { $0 == request }
            try await store.save(state)
            submitted.append(request)
        }
        return submitted
    }
}

extension TaskNotificationRequest {
    func replacingEvents(_ events: [TaskNotificationEvent]) -> TaskNotificationRequest? {
        guard !events.isEmpty else { return nil }
        return TaskNotificationRequest(taskID: taskID, title: title, kind: events.count == 2 ? .combined : events[0].source == .planned ? .planned : .due, fireDate: fireDate, events: events)
    }
}
