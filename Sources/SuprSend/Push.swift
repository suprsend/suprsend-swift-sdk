import Foundation
import UserNotifications
#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit.UIApplication
#endif

@objc public protocol SuprSendPushNotificationDelegate: AnyObject {
    func pushNotificationTapped(withCustomExtras customExtras: [AnyHashable : Any]!)
}

/// A class responsible for handling push notifications.
public class Push {
    private let config: SuprSendClient
    
    private let queue: PushQueue
    
    var delegate: SuprSendPushNotificationDelegate?

    init(config: SuprSendClient) {
        self.config = config
        self.queue = PushQueue(config: config)
    }

    func flushPendingEvents() {
        queue.flushPendingEvents()
    }

    func getPushSubscription() async -> String? {
        if let token = config.deviceToken {
            return token
        }
        if await notificationPermission() == .authorized {
#if os(iOS) || os(watchOS) || os(tvOS)
            await UIApplication.shared.registerForRemoteNotifications()
#endif
            return nil
        }
        return nil
    }

    /// Whether the device currently has a push token the SDK can attach to a
    /// tenant. Mirrors `pushSubscribed()` in suprsend-web-sdk.
    public func pushSubscribed() -> Bool {
        config.deviceToken != nil
    }

    /// Attaches the device's push token to the identified user on the active
    /// tenant.
    /// - Returns: The API response, or a `.notFound` error when the device has
    ///   no push token yet (in which case nothing is sent).
    @discardableResult
    public func updatePushSubscription() async -> APIResponse {
        guard let subscription = await getPushSubscription() else {
            return .error(.init(type: .notFound, message: "Push subscription not found"))
        }
        return await config.user.addiOSPush(subscription)
    }

    /// Detaches the device's push token from the identified user on the active
    /// tenant.
    /// - Returns: The API response, or a `.notFound` error when the device has
    ///   no push token (in which case nothing is sent).
    @discardableResult
    public func removePushSubscription() async -> APIResponse {
        guard let subscription = await getPushSubscription() else {
            return .error(.init(type: .notFound, message: "Push subscription not found"))
        }
        return await config.user.removeiOSPush(subscription)
    }

    /// Retrieves the current notification permission status.
    /// - Returns: The current notification permission status.
    public func notificationPermission() async -> UNAuthorizationStatus {
        if UIApplication.shared.delegate != nil {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        } else {
            UNAuthorizationStatus.notDetermined
        }
    }

    /// Registers for push notifications.
    /// - Note: This method currently returns a placeholder response and should be implemented to retrieve the actual device token.
    /// - Returns: A placeholder API response indicating success.
    public func registerPush() async throws -> APIResponse {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .sound, .badge,
        ])
        if granted {
            logger.info("Notification permission granted.")
        } else {
            logger.warning("Notification permission denied.")
        }
        return .success()
    }
    
}

extension Push {
    
    public func isSuprSendNotification(_ notification: UNNotificationResponse) -> Bool {
        isSuprSendNotificationInfo(notification.notification.request.content.userInfo)
    }
    
    public func isSuprSendNotification(_ notification: UNNotification) -> Bool {
        isSuprSendNotificationInfo(notification.request.content.userInfo)
    }
    
    func isSuprSendNotificationInfo(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo.keys.contains("via_suprsend")
    }
}

extension Push {
    func trackNotificationDelivered(userInfo: [AnyHashable: Any]) async {
        if isSuprSendNotificationInfo(userInfo),
            let nid = userInfo["nid"] as? String {
            queue.push(.init(event: "$notification_delivered", nid: nid))
        }
    }
    
    func trackNotificationClicked(userInfo: [AnyHashable: Any]) async {
        if isSuprSendNotificationInfo(userInfo),
           let nid = userInfo["nid"] as? String {
            queue.push(.init(event: "$notification_clicked", nid: nid))
        }
    }
    
    func trackNotificationDismissed(userInfo: [AnyHashable: Any]) async {
        if isSuprSendNotificationInfo(userInfo),
           let nid = userInfo["nid"] as? String {
            queue.push(.init(event: "$notification_dismiss", nid: nid))
        }
    }
}

// MARK: - AppDelegate Functions Mapping
extension Push {
    private func handleGlobalActionURL(response: UNNotificationResponse) {
        let actionURL = response.notification.request.content.userInfo["global_action_url"] as? String
        if let actionURL,
            let url = URL(string: actionURL) {
            let handleLink = config.urlDelegate?.shouldHandleSuprSendDeepLink(url) ?? true
            if handleLink {
#if os(iOS) || os(watchOS) || os(tvOS)
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
#endif
            }
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task {
            if response.actionIdentifier == UNNotificationDismissActionIdentifier {
                await trackNotificationDismissed(userInfo: response.notification.request.content.userInfo)
            } else {
                await trackNotificationClicked(userInfo: response.notification.request.content.userInfo)
            }
            
            handleGlobalActionURL(response: response)
            
            delegate?.pushNotificationTapped(withCustomExtras: response.notification.request.content.userInfo)
        }
    }
    
#if os(iOS) || os(watchOS) || os(tvOS)
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await trackNotificationDelivered(userInfo: userInfo)
        }
    }
#endif
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task {
            await trackNotificationDelivered(userInfo: notification.request.content.userInfo)
            
            await trackNotificationClicked(userInfo: notification.request.content.userInfo)
        }
    }
}

// MARK: - NotificationService Functions Mapping
extension Push {
    public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        Task {
            await trackNotificationDelivered(userInfo: request.content.userInfo)
        }
    }
}
