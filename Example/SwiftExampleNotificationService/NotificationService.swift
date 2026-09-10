import UserNotifications
import SuprSend

// Duplicated from the app: extension targets can't share files under synchronized groups.
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
