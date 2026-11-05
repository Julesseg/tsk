#if canImport(UserNotifications)
import Foundation
import Testing
import TskCore
@testable import TskNative
@preconcurrency import UserNotifications

@Test func nativeTaskAlertsUseCleanTimeSensitiveContentAndRecognizeLegacyRegistrations() throws {
    let instant = Date(timeIntervalSince1970: 1792100000)
    let tasks = [
        TaskRecord(id: UUID(), attributes: ["description": "Due task", "status": "pending", "due": "1792141200"]),
        TaskRecord(id: UUID(), attributes: ["description": "Planned task", "status": "pending", "scheduled": "1792141200"]),
        TaskRecord(id: UUID(), attributes: ["description": "Combined task", "status": "pending", "scheduled": "1792141200", "due": "1792141200"])
    ]
    let plan = try TaskManager.notificationPlan(tasks: tasks, preferences: .init(midnightReplacement: false), at: instant)
    #expect(plan.future.count == 3)
    for request in plan.future {
        let content = try UNTaskNotificationCenter.content(for: request)
        #expect(content.title == request.title)
        switch request.kind {
        case .due: #expect(content.body.isEmpty)
        case .planned: #expect(content.body == "Planned work")
        case .combined: #expect(content.body == "Planned and due")
        }
        if #available(iOS 15, macOS 12, *) { #expect(content.interruptionLevel == .timeSensitive) }
        #expect(content.sound != nil)
        #expect(content.userInfo["taskID"] as? String == request.taskID.uuidString)
        for identifier in [request.identifier, request.immediateIdentifier] {
            let native = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let pending = UNTaskNotificationCenter.pendingNotification(native)
            #expect(pending.request == request)
            #expect(pending.contentMatchesRequest)
        }
        if #available(iOS 15, macOS 12, *) { content.interruptionLevel = .active }
        let legacy = UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil)
        if #available(iOS 15, macOS 12, *) { #expect(!UNTaskNotificationCenter.pendingNotification(legacy).contentMatchesRequest) }
        content.body = "Task is due (missed while away)"
        if #available(iOS 15, macOS 12, *) { content.interruptionLevel = .timeSensitive }
        let missed = UNNotificationRequest(identifier: request.immediateIdentifier, content: content, trigger: nil)
        #expect(!UNTaskNotificationCenter.pendingNotification(missed).contentMatchesRequest)
        #expect(UNTaskNotificationCenter.pendingNotification(missed).request == request)
    }
}
#endif
