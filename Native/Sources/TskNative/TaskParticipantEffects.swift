import Foundation
import TskCore

public enum TaskParticipantEffects {
    public static func make(directory: URL) -> TaskPostCommitEffects {
        #if os(iOS)
        return TaskPostCommitEffects([TaskNotificationEffect(directory: directory)])
        #else
        return TaskPostCommitEffects()
        #endif
    }
}
