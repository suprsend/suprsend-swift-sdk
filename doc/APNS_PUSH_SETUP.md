# APNs Push Setup

### Prerequisites

- [Integration of SuprSend Swift SDK](../README.md#integration-steps)
- Configuring the iOS vendor form in the SuprSend Dashboard

> **Tip:**
> A working example can be found in the
> [`Example/`](https://github.com/suprsend/suprsend-swift-sdk/tree/main/Example)
> app.

## Step 1: Add push capability

Inside your Target select **Signing & Capabilities**, click **+ Capability** and
add **Push Notifications**.

![Add the Push Notifications capability in Xcode](https://mintcdn.com/suprsend/3ix_OjxB_ZGM-pa-/images/docs/29bafbe-Screenshot_2022-05-19_at_5.48.52_PM.png?fit=max&auto=format&n=3ix_OjxB_ZGM-pa-&q=85&s=6dc8960bc305b9ff439cfd265cd4f1dc)

Add **Background Modes** the same way, then tick **Remote notifications**. This
lets APNs wake the app so delivery of background notifications can be tracked.

![Enable Background Modes → Remote notifications](https://mintcdn.com/suprsend/09Y8zJBSaqwwb23r/images/docs/75c5310-Screenshot_2022-09-27_at_1.48.11_PM.png?fit=max&auto=format&n=09Y8zJBSaqwwb23r&q=85&s=3455b9ac0218ac1621399be197c1b46a)

## Step 2: Register for push notifications

`AppDelegate` should implement `UNUserNotificationCenterDelegate` from
`UserNotifications`. Add a `registerForPush` method and call it inside
`application(_:didFinishLaunchingWithOptions:)`.

```swift
import UserNotifications // Add this
import SuprSend

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_KEY")
    registerForPush() // add this
    return true
  }

  // add this method
  func registerForPush() {
    UNUserNotificationCenter.current().delegate = self // this will register the push delegate

    // Ask the user for permission.
    // options = [.sound, .badge, .alert] for explicit authorization
    // options = [.sound, .badge, .alert, .provisional] for provisional authorization
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.sound, .badge, .alert]
    ) { granted, error in
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }
}
```

### Step 2.1: Asking user permission

The `options` you pass to `requestAuthorization` decide how the user is prompted
for permission.

#### Explicit Authorization

Explicit authorization allows you to display alerts, add a badge to the app icon,
or play sounds whenever a notification is delivered. In this type of
authorization the request is made the first time the user launches your app. If
the user denies the request, you can't send subsequent prompts to send the
notification.

```swift
UNUserNotificationCenter.current().requestAuthorization(
  options: [.sound, .badge, .alert]
) { granted, error in
  // ...
}
```

> **Note**
> Explicit authorization is the default authorization method, as it
> automatically sets alert, sound and badge as soon as the user allows this
> request.

![Explicit authorization permission prompt](https://mintcdn.com/suprsend/JOwfEC79k-vs3tUR/images/docs/8538f91-app_permission.png?fit=max&auto=format&n=JOwfEC79k-vs3tUR&q=85&s=3e3be8e0b3762dd835a490e6c4c1af7f)

#### Provisional Authorization

Provisional authorization (supported in iOS 12.0 and above) sends notifications
quietly to the users — they don't interrupt the user with a sound or banner, and
they are not shown when your app is in the foreground. The first time this type
of notification is sent, the user is asked to **Keep** or **Turn off** the
notifications. Further notifications continue to be sent if they click on
"Keep".

```swift
UNUserNotificationCenter.current().requestAuthorization(
  options: [.sound, .badge, .alert, .provisional]
) { granted, error in
  // ...
}
```

![Provisional authorization notification example](https://mintcdn.com/suprsend/ftswjUsq0JlUh-RL/images/docs/0367021-provisional.png?fit=max&auto=format&n=ftswjUsq0JlUh-RL&q=85&s=c44246faebb35ddb646e77c3ea29a522)

## Step 3: Add delegate methods for push handling

Add the following methods to `AppDelegate` to hand the APNs token to SuprSend and
forward notification lifecycle events, so delivery and clicks are tracked:

```swift
// APNs returned the device token — forward it to SuprSend.
func application(
  _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
  let token = tokenParts.joined()

  Task {
    _ = await SuprSend.shared.user.addiOSPush(token)
  }
}

// Background / silent notification delivery.
func application(
  _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
  fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
  SuprSend.shared.push.application(
    application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)

  completionHandler(.newData)
}

// User tapped or dismissed a notification.
func userNotificationCenter(
  _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  SuprSend.shared.push.userNotificationCenter(
    center, didReceive: response, withCompletionHandler: completionHandler)

  completionHandler()
}

// Notification shown while the app is in the foreground.
func userNotificationCenter(
  _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
  SuprSend.shared.push.userNotificationCenter(
    center, willPresent: notification, withCompletionHandler: completionHandler)

  if #available(iOS 14.0, *) {
    completionHandler([.banner, .badge, .sound])
  } else {
    // Fallback on earlier versions
    completionHandler([.alert, .badge, .sound])
  }
}
```

> **Note**
> The token is associated with the current user automatically and cleared on
> [`SuprSend.shared.reset()`](../README.md#step-3-reset-user), so notifications
> stop after logout.

## Step 4: Adding support for Notification Service Extension

A Notification Service Extension lets APNs payloads be modified before display —
for example to download and attach an image — and improves delivery tracking.
Add it if you send rich (image/media) notifications.

### Step 4.1: Add the Notification Service Extension

1. In Xcode go to **File > New > Target**.
2. Select **Notification Service Extension** from the template list.
3. In the next popup give it any product name, select your team, select Swift as
   the language and click **Finish**.

![Naming the Notification Service target](https://mintcdn.com/suprsend/3ix_OjxB_ZGM-pa-/images/docs/2545534-Screenshot_2022-09-27_at_8.23.30_PM.png?fit=max&auto=format&n=3ix_OjxB_ZGM-pa-&q=85&s=7d5b605ac23ad4753e43f6bbfc846424)

After clicking "Finish", a folder will be created with your given product name,
containing `NotificationService.swift` and `Info.plist`.

![NotificationService.swift inside the new folder](https://mintcdn.com/suprsend/09Y8zJBSaqwwb23r/images/docs/507d91a-Screenshot_2022-09-27_at_8.30.25_PM.png?fit=max&auto=format&n=09Y8zJBSaqwwb23r&q=85&s=844b510f372bafdcb4ff19dc6120c314)

### Step 4.2: Install the SuprSend SDK in the Notification Service

**Swift Package Manager (SPM)**

In Xcode, go to **File > Add Package Dependencies**. In the search bar add the
project URL `https://github.com/suprsend/suprsend-swift-sdk`, keep the default
version settings and click **Add Package**. In the second dialog, select your
Notification Service target from the dropdown and click **Add Package**.

**CocoaPods**

**For SDK version `1.1.0` onwards**, add the SDK to your Podfile as a dependency
of the Notification Service Extension target, then run `pod install`:

```ruby
target '<your_notification_service_name>' do
  pod 'SuprSendSwift', :git => 'https://github.com/suprsend/suprsend-swift-sdk.git', :tag => '2.0.0'
end
```

**For SDK versions till `1.0.1`**, add it as below and then run `pod install`:

```ruby
target '<your_notification_service_name>' do
  pod "SuprSendSwift"
end
```

![Podfile with the NotificationService target](https://mintcdn.com/suprsend/JOwfEC79k-vs3tUR/images/docs/8397e64-Screenshot_2024-08-14_at_4.34.21_PM.png?fit=max&auto=format&n=JOwfEC79k-vs3tUR&q=85&s=3e0c42ccbf163298ffb941ca71a249f2)

### Step 4.3: Add code in the Notification Service

Replace the generated code in `NotificationService.swift` with the below and add
a valid public API key in place of `YOUR_PUBLIC_KEY`.

```swift
import UserNotifications
import SuprSend

final class NotificationService: SuprSendNotificationService {
  // Must match the public key passed to SuprSend.shared.configure(...) in your AppDelegate.
  override func publicKey() -> String {
    "YOUR_PUBLIC_KEY"
  }

  // Optional — only needed if your app passes a custom host.
  override func options() -> SuprSend.Options? {
    SuprSend.Options(host: "YOUR_HOST")
  }
}
```

> **Note**
> With CocoaPods, `import SuprSendSwift` instead and use
> `SuprSendSwift.Options`.

That's it — you are all set to test your APNs push.

## Handling deep links

By default the SDK will handle only http deeplinks. If you want to handle custom
deeplinks, implement `SuprSendDeepLinkDelegate` in your `AppDelegate` class and
add the below code.

```swift
// implement SuprSendDeepLinkDelegate
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate,
  SuprSendDeepLinkDelegate
{
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_KEY")
    SuprSend.shared.setDeepLinkDelegate(self)  // Add this
    registerForPush()
    return true
  }

  func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool {
    print("Handling URL: \(url)")  // write your linking logic here and return true
    return true
  }
}
```

Return `true` from `shouldHandleSuprSendDeepLink` when you have handled the URL
yourself; return `false` to let the SDK open it.

The delegate can also be passed directly while configuring the client:

```swift
SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_KEY", urlDelegate: self)
```

## Push notification click callback

To run your own code when a SuprSend notification is tapped, implement
`SuprSendPushNotificationDelegate` on the same object you pass as the delegate.
Custom key-value pairs added to the notification payload are handed back to you.

```swift
extension AppDelegate: SuprSendPushNotificationDelegate {
  func pushNotificationTapped(withCustomExtras customExtras: [AnyHashable: Any]!) {
    print("Push tapped with extras: \(customExtras.debugDescription)")
  }
}
```

## Final AppDelegate.swift file

Example of an `AppDelegate.swift` file with all of the above code.

```swift
import Foundation
import SuprSend
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate,
  SuprSendDeepLinkDelegate
{

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    SuprSend.shared.enableLogging()
    SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_KEY")
    SuprSend.shared.setDeepLinkDelegate(self)
    registerForPush()
    return true
  }

  func registerForPush() {
    UNUserNotificationCenter.current().delegate = self

    UNUserNotificationCenter.current().requestAuthorization(
      options: [.sound, .badge, .alert]
    ) { granted, error in
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }

  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()

    Task {
      _ = await SuprSend.shared.user.addiOSPush(token)
    }
  }

  func application(
    _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    SuprSend.shared.push.application(
      application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler
    )

    completionHandler(.newData)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    SuprSend.shared.push.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)

    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    SuprSend.shared.push.userNotificationCenter(
      center, willPresent: notification, withCompletionHandler: completionHandler)

    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      // Fallback on earlier versions
      completionHandler([.alert, .badge, .sound])
    }
  }

  func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool {
    print("Handling URL: \(url)")
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }
}
```

## Other push methods

```swift
// Current notification permission status.
let status: UNAuthorizationStatus = await SuprSend.shared.push.notificationPermission()

// Check whether a notification originated from SuprSend, before handling it yourself.
SuprSend.shared.push.isSuprSendNotification(notification)

// Remove the push subscription for the current device without resetting the user.
await SuprSend.shared.push.removePushSubscription()

// Remove a stored APNs token from the user profile.
await SuprSend.shared.user.removeiOSPush(token)
```
