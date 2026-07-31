# SuprSend Swift SDK

This SDK is used to integrate SuprSend features like Mobile Push, Preferences and InApp feed in to your iOS application.

> 📘 This is the new `SuprSend` iOS SDK
>
> `SuprSendSdk` is deprecated. If you are still on the older SDK, refer its
> [documentation](https://github.com/suprsend/SuprSend-iOS-SDK/tree/main/documentation)
> and migrate to this SDK.

## Installation

**Requirements:** iOS 15.0+ (macOS 12.0+), Swift 5.

### Swift Package Manager (SPM)

In Xcode, go to **File > Add Package Dependencies**. In the search bar, add the
project URL `https://github.com/suprsend/suprsend-swift-sdk`, keep the default
version settings and click **Add Package**. In the second dialog, select your
project's target from the dropdown and click **Add Package**.

### CocoaPods

**For SDK version `1.1.0` onwards**, add the SDK to your Podfile using the
GitHub source and run `pod install`:

```ruby
pod 'SuprSendSwift', :git => 'https://github.com/suprsend/suprsend-swift-sdk.git', :tag => '2.0.0'
```

**For SDK versions till `1.0.1`**, add `pod "SuprSendSwift"` to your Podfile and
run `pod install`.

> **Note**
> The module name differs by installation method: `import SuprSend` with SPM and
> `import SuprSendSwift` with CocoaPods. The examples below use `SuprSend.shared`
> (the SPM form) — on CocoaPods use `SuprSendClient.shared`, which works with
> both.

## Integration Steps

### Step 1: Create Client Instance

Import the SDK inside `AppDelegate.swift` and initialize the SuprSend client
inside `application(_:didFinishLaunchingWithOptions:)`. All the methods of the
SuprSend SDK can be accessed only after configuring the client.

```swift
import SuprSend

func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
) -> Bool {
  SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_KEY")
  return true
}
```

| Parameter     | Description                                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `publicKey*`  | **Required.** Your workspace public key from the SuprSend dashboard (**ApiKeys → Public Keys**).                                |
| `options`     | Optional. `SuprSend.Options(host:appInfo:clientUserAgent:)` — custom API host and app name/version advertised in the user agent. |
| `urlDelegate` | Optional. `SuprSendDeepLinkDelegate` used to handle custom deep links on notification click. See [APNs Push Setup](doc/APNS_PUSH_SETUP.md#handling-deep-links). |

### Step 2: Authenticate User

Authenticate user so that all the actions performed after authenticating will be
w.r.t that user. This is a mandatory step and needs to be called before using any
other method. This is usually performed after successful login and on app launch
to re-authenticate the user (can be changed based on your requirement).

```swift
await SuprSend.shared.identify(
  distinctID: "user-distinct-id",
  userToken: jwt, // only needed in production environments for security
  tenantId: "tenant-id", // only needed in multi-tenant workspaces
  options: AuthenticateOptions(
    refreshUserToken: { oldUserToken, tokenPayload in
      return await myBackend.fetchSuprSendToken()
    }
  )
)
```

| Properties         | Description                                                                                                                                                                                                          |
| :----------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `distinctID*`      | Unique identifier to identify a user across platform.                                                                                                                                                                |
| `userToken`        | Mandatory when enhanced security mode is on. This is an ES256 JWT token generated in your server-side. Refer [docs](https://docs.suprsend.com/docs/client-authentication#enhanced-security-mode-with-signed-user-token) to create userToken. |
| `tenantId`         | Needed only when your workspace has multiple tenants/brands. Scopes the identified user's activity to that tenant. Its value must match `scope.tenant_id` in the `userToken` payload, else it raises a scoping error. |
| `options`          | `AuthenticateOptions(refreshUserToken:)`. The `refreshUserToken` closure is called by the SDK internally to get a new userToken before the existing one expires. The returned string is used as the new userToken.    |

**Returns:** `async -> APIResponse`

#### 2.1 Check if user is authenticated

This method checks if a user is authenticated i.e. `distinctID` is attached to
the SuprSend instance. To check for `userToken` as well, pass `checkUserToken` as
`true`.

```swift
SuprSend.shared.isIdentified(checkUserToken: true)
```

### Step 3: Reset User

This will remove user data from the SuprSend instance, similar to a logout
action.

```swift
await SuprSend.shared.reset()
```

**Returns:** `async -> APIResponse`

## Change active tenant

Use the below method to switch the active tenant of an identified user. Intended
for users whose token scopes multiple tenants — identify once, then switch
without resetting the session.

```swift
SuprSend.shared.changeTenant(tenantId: "tenant-id")
```

> **Note**
> Already-running feed instances keep the tenant they were initialised with —
> re-initialise the feed to reflect the new tenant, and re-fetch preferences via
> `getPreferences` to load the new tenant's data.

## Features

- [APNs Push Setup](doc/APNS_PUSH_SETUP.md) — capabilities, permission prompt, device token registration, notification service extension and deep links.
- [Events and User methods](doc/EVENTS_AND_USER_METHODS.md) — trigger events and update user channels and properties.
- [InApp Feed (Headless)](doc/INBOX.md) — fetch notifications, realtime updates and notification states.
- [Preferences](doc/PREFERENCES.md) — build a notification preference center.

## Logging

Add the below code next to the client configuration in `AppDelegate` to see logs
for debugging.

```swift
SuprSend.shared.enableLogging()
```

## API Response

All SuprSend SDK methods return an `APIResponse`. Use it to check whether a call
succeeded and to read error details when it didn't.

```swift
public class APIResponse: NSObject, Response {
  /// The status of the response (success or error).
  public let status: ResponseStatus

  /// The HTTP status code associated with the response.
  public let statusCode: StatusCode?

  /// The JSON response body.
  public let body: ResponseBody?

  /// Any error that occurred during the request. {type, message}
  public let error: ResponseError?
}
```

```swift
let response = await SuprSend.shared.user.addEmail("user@example.com")
switch response.status {
case .success:
  break // handle success
case .error:
  print("\(response.error?.type?.rawValue ?? ""): \(response.error?.message ?? "")")
}
```

| Property     | Description                                                                          |
| :----------- | :------------------------------------------------------------------------------------ |
| `status`     | `.success` or `.error`.                                                              |
| `statusCode` | HTTP status code, when available.                                                    |
| `body`       | JSON response body, when available.                                                  |
| `error`      | `ResponseError` with `type` (e.g. `.validation`, `.network`) and `message`.           |

> **Note**
> `getPreferences` and the preference update methods return
> `PreferenceAPIResponse`, and the feed methods return `FeedAPIResponse` /
> `FeedCountAPIResponse` / `FeedDetailAPIResponse`. All follow the same
> `status` / `statusCode` / `body` / `error` shape with a typed `body`.

## Example

A full example app is available in [`Example/`](Example).

## Documentation

Full documentation is available at
[docs.suprsend.com/docs/ios-integration](https://docs.suprsend.com/docs/ios-integration).
