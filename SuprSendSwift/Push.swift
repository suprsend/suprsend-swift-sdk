//
//  Push.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 30/08/24.
//

import Foundation
import UserNotifications

/// A class responsible for handling push notifications.
public class Push {
    /// The configuration instance used to manage user data.
    private let config: SuprSend

    /// Initializes a new `Push` instance with the given configuration.
    ///
    /// - Parameter config: The configuration instance to use.
    init(config: SuprSend) {
        self.config = config
    }

    /// Retrieves the push subscription, if available.
    ///
    /// - Returns: The push subscription as a string, or `nil` if not available.
    func getPushSubscription() async -> String? {
        nil
    }

    /// Updates the push subscription by adding it to the user's configuration.
    ///
    /// - Note: This method will only update the subscription if one is available.
    public func updatePushSubscription() async {
        let subscription = await getPushSubscription()
        if let subscription {
            _ = await self.config.user.addPush(subscription)
        }
    }

    /// Removes the push subscription from the user's configuration.
    ///
    /// - Note: This method will only remove the subscription if one is available.
    public func removePushSubscription() async {
        let subscription = await getPushSubscription()
        if let subscription {
            _ = await self.config.user.removePush(subscription)
        }
    }

    /// Retrieves the current notification permission status.
    ///
    /// - Returns: The current notification permission status.
    func notificationPermission() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Registers for push notifications.
    ///
    /// - Note: This method currently returns a placeholder response and should be implemented to retrieve the actual device token.
    ///
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
