//
//  Push.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/08/24.
//

import Foundation
import UserNotifications
#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#endif

/// A class responsible for handling push notifications.
public class Push {
    /// The configuration instance used to manage user data.
    private let config: SuprSendClient
    
    private let queue: PushQueue

    /// Initializes a new `Push` instance with the given configuration.
    /// - Parameter config: The configuration instance to use.
    init(config: SuprSendClient) {
        self.config = config
        self.queue = PushQueue(config: config)
    }

    /// Retrieves the push subscription, if available.
    /// - Returns: The push subscription as a string, or `nil` if not available.
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

    /// Updates the push subscription by adding it to the user's configuration.
    /// - Note: This method will only update the subscription if one is available.
    public func updatePushSubscription() async {
        let subscription = await getPushSubscription()
        if let subscription {
            _ = await self.config.user.addiOSPush(subscription)
        }
    }

    /// Removes the push subscription from the user's configuration.
    /// - Note: This method will only remove the subscription if one is available.
    public func removePushSubscription() async {
        let subscription = await getPushSubscription()
        if let subscription {
            _ = await self.config.user.removeiOSPush(subscription)
        }
    }

    /// Retrieves the current notification permission status.
    /// - Returns: The current notification permission status.
    public func notificationPermission() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Registers for push notifications.
    /// - Note: This method currently returns a placeholder response and should be implemented to retrieve the actual device token.
    /// - Returns: A placeholder API response indicating success.
    func registerPush() async throws -> APIResponse {
        // TODO: Get push notification device token
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .sound, .badge,
        ])
        if granted {
            print("Notification permission granted.")
        } else {
            print("Notification permission denied.")
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
            if config.urlDelegate?.shouldHandleSuprSendDeepLink(url) == true {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
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
