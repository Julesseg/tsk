import Foundation
import TskCore

public enum TaskParticipantEffects {
    public static func make(directory: URL) -> TaskPostCommitEffects {
        #if os(iOS)
        if #available(iOS 17.0, *) { return TaskPostCommitEffects([TaskNotificationEffect(directory: directory), SpotlightTaskEffect(directory: directory)]) }
        return TaskPostCommitEffects([TaskNotificationEffect(directory: directory)])
        #else
        return TaskPostCommitEffects()
        #endif
    }
}
