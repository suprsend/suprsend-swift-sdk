//
//  AppDelegate.swift
//  ECommerceAppSwiftUI
//
//  Created by Ram Suthar
//
//

import UIKit
import SuprSend
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        SuprSend.shared.configure(
            publicKey: SuprSendConstants.publicKey,
            options: SuprSend.Options(host: SuprSendConstants.host),
            urlDelegate: self
        )
        
        SuprSend.shared.enableLogging()
        let isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        if isLoggedIn,
           let email = UserDefaults.standard.string(forKey: "email") {
            CommonAnalyticsHandler.identify(identity: email)
        }

        registerForPush()
    
        return true
    }
    
    func registerForPush() {
        // Register for Push notifications
        UNUserNotificationCenter.current().delegate = self
        
        // request Permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .badge, .alert], completionHandler: {granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        })
    }
}

extension AppDelegate: UIApplicationDelegate {
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        print("Device Token: \(token)")
        
        Task {
            await SuprSend.shared.user.addiOSPush(token)
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        SuprSend.shared.push.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)

        completionHandler(.newData)
    }
    
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if let scheme = url.scheme,
            scheme.localizedCaseInsensitiveCompare("com.ecommerceApp") == .orderedSame,
            let view = url.host {
            
            var parameters: [String: String] = [:]
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach {
                parameters[$0.name] = $0.value
            }
            
        }
        return true
    }

}

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        SuprSend.shared.push.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        SuprSend.shared.push.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
        
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .badge, .sound])
        } else {
            // Fallback on earlier versions
            completionHandler([.alert, .badge, .sound])
        }
    }
}

extension AppDelegate: SuprSendDeepLinkDelegate {
    func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool {
        print("Handling URL: \(url)")
        return true
    }
}

extension AppDelegate: SuprSendPushNotificationDelegate {
    func pushNotificationTapped(withCustomExtras customExtras: [AnyHashable : Any]!) {
        print("Push Notification Tapped with Custom Extras: \(customExtras.debugDescription)")
    }
}
