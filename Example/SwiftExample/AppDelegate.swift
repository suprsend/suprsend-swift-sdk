import UIKit
import SuprSend
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    let router = AppRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        SuprSend.shared.configure(
            publicKey: SuprSendConstants.publicKey,
            options: SuprSend.Options(host: SuprSendConstants.host, appInfo: AppInfo(name: "Swift example app", version: "1.0.0")),
            urlDelegate: self
        )
        SuprSend.shared.enableLogging()

        if let storedDistinctID = UserDefaults.standard.string(forKey: SuprSendConstants.distinctIDKey),
           !storedDistinctID.isEmpty {
            Task {
                await SuprSendTokenService.identify(distinctID: storedDistinctID)
            }
        }

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[SwiftExample] Device token: \(token)")
        Task {
            _ = await SuprSend.shared.user.addiOSPush(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[SwiftExample] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        SuprSend.shared.push.application(
            application,
            didReceiveRemoteNotification: userInfo,
            fetchCompletionHandler: completionHandler
        )
        completionHandler(.newData)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        SuprSend.shared.push.userNotificationCenter(
            center, willPresent: notification, withCompletionHandler: completionHandler
        )
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        SuprSend.shared.push.userNotificationCenter(
            center, didReceive: response, withCompletionHandler: completionHandler
        )
        completionHandler()
    }
}

extension AppDelegate: SuprSendDeepLinkDelegate {
    func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool {
        print("[SwiftExample] Deeplink: \(url)")
        router.handle(url: url)
        return true
    }
}

extension AppDelegate: SuprSendPushNotificationDelegate {
    func pushNotificationTapped(withCustomExtras customExtras: [AnyHashable: Any]!) {
        print("[SwiftExample] Push tapped with extras: \(customExtras.debugDescription)")
    }
}
