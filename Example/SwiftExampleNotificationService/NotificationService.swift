import UserNotifications
import SuprSend

// Keep these values in sync with SwiftExample/SuprSendConstants.swift.
// Extension targets cannot share files with the main app target when the
// app uses Xcode's file system synchronized groups.
private enum NSEConstants {
    static let publicKey: String = ""
    static let host: String? = nil
}

final class NotificationService: SuprSendNotificationService {
    override func publicKey() -> String {
        NSEConstants.publicKey
    }

    override func options() -> SuprSend.Options? {
        SuprSend.Options(host: NSEConstants.host)
    }
}
