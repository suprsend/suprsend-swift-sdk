# SuprSend Swift SDK

Install and initialize the SuprSend iOS Swift SDK in your mobile app to enable push, in-app inbox, preferences, and user identification features.

> **Warning**
> **`SuprSendSdk` is deprecated. Please migrate to `SuprSend` SDK**
>
> This documentation is for new version of iOS sdk. If you are using older version of sdk `SuprSendSdk` please refer [documentation](https://github.com/suprsend/SuprSend-iOS-SDK/tree/main/documentation)

- [APNS Push Integration](doc/APNS_PUSH_SETUP.md)
- [Events and User methods](doc/EVENTS_AND_USER_METHODS.md)
- [InApp Feed (Headless)](doc/INBOX.md)
- [Preferences](doc/PREFERENCES.md)

## Installation

There are two ways you can install SuprSend SDK into your app:

### Swift Package Manager (SPM)

In Xcode, go to File > AddPackages to add a new dependency.

In that search bar, add suprsend-swift-sdk project github url `https://github.com/suprsend/suprsend-swift-sdk` and keep the default version settings and click `Add Package` button.

In second dialog box, select your project's target from dropdown and click `Add Package` button.

### Cocoapods

**For SDK version `1.1.0` onwards**, add the SDK to your Podfile using the GitHub source and run `pod install`:

```ruby
pod 'SuprSendSwift', :git => 'https://github.com/suprsend/suprsend-swift-sdk.git', :tag => '1.1.0'
```

**For SDK versions till `1.0.1`**, add the SuprSendSwift SDK to your Podfile as `pod "SuprSendSwift"` and run `pod install` to install the SDK.

## Integration

### Step 1: Create Client

Import SDK inside `AppDelegate.swift` and then initialize the SuprSend class inside `application(_:didFinishLaunchingWithOptions:)` method.

```swift
import SuprSend

SuprSend.shared.configure(publicKey: "YOUR_PUBLIC_API_KEY")
```

| Params         | Description                                                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| publicApiKey\* | This is public Key used to authenticate API calls to SuprSend. Get it in SuprSend dashboard **ApiKeys -> Public Keys** section |

### Step 2: Authenticate User

Authenticate user so that all the actions performed after authenticating will be w.r.t that user. This is mandatory step and need to be called before using any other method. This is usually performed after successful login and on reload of page to re-authenticate user.

```swift
await SuprSend.shared.identify(distinctID: "YOUR_USER_ID", userToken: userTokenData, tenantId: "TENANT_ID", options: AuthenticateOptions(refreshUserToken: {oldUserToken,tokenPayload in return refreshedUserToken()}));
```

| Properties       | Description                                                                                                                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| distinctId\*     | Unique identifier to identify a user across platform.                                                                                                                                                            |
| userToken        | Mandatory when enhanced security mode is on. This is ES256 JWT token generated in your server-side. Refer [docs](https://docs.suprsend.com/docs/client-authentication#enhanced-security-mode-with-signed-user-token) to create userToken. |
| tenantId         | Needed only when your workspace has multiple tenants/brands. Scopes the identified user's activity to that tenant. Its value must match `scope.tenant_id` in the `userToken` payload, else it raises a scoping error. |
| refreshUserToken | This function is called by SDK internally to get new userToken before existing token is expired. The returned string is used as the new userToken.                                                               |

**Returns:** `async -> APIResponse`

#### 2.1 Check if user is authenticated

This method will check if user is authenticated i.e. `distinctId` is attached to SuprSend instance. To check for userToken also pass checkUserToken flag true.

```swift
SuprSend.shared.isIdentified(checkUserToken: true)
```

### Step 3: Reset user

This will remove user data from SuprSend instance. This is usually called on logout action.

```swift
await SuprSend.shared.reset()
```

**Returns:** `async -> APIResponse`

## Change active tenant

Use the below method to switch the active tenant of identified user. This is meant for users whose `userToken` scopes multiple tenants (`scope.tenant_id` as an array) - identify once and switch between them without resetting the session.

```swift
SuprSend.shared.changeTenant(tenantId: "TENANT_ID")
```

| Properties | Description                                                                                                                            |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| tenantId\* | Tenant to switch to. Used by subsequent preferences requests and newly initialized feeds. Must be one of the tenants scoped in `userToken`. |

> **Note**
> Already running feed instances keep the tenant they were initialized with - re-initialize the feed to reflect the new tenant, and call `getPreferences` again to load the new tenant's data.

## Response Structure

```swift
struct APIResponse {
  /// The status of the response (success or error).
  public let status: ResponseStatus

  /// The HTTP status code associated with the response.
  public let statusCode: StatusCode?

  /// The JSON response body.
  public let body: ResponseBody?

  /// Any error that occurred during the request. {type: string, message: string}
  public let error: ResponseError?

}
```
