# SwiftExample

A minimal SwiftUI iOS app that integrates the [SuprSend Swift SDK](../)
from this repository as a local Swift Package.

## What it covers

- **Login screen** — enter a distinct id to identify the user
- **Home screen** — buttons for Preferences, Inbox, Add/Remove email, Track event, Logout
- **Preferences screen** — category and channel-level notification preferences
  (toggle, channel chips, expandable "All / Required" per-channel controls)
- **Inbox screen** — feed-backed inbox with stores (All / Unread / Archived /
  Transactional / custom tag), real-time updates over socket, mark as
  read/unread/archived, pagination, badge counts
- **Push notifications** — registers for APNs and reports the token via
  `SuprSend.shared.user.addiOSPush`, and includes a Notification Service
  Extension target for rich media payloads
- **Deep links** — `suprsendswiftexample://home`, `://preferences`, `://inbox`

## SDK source

The project references the SDK as a **local Swift Package** at relative
path `..` (the repo root). If you copy `Example/` out of this repository,
update `relativePath` in `SwiftExample.xcodeproj/project.pbxproj` (search
for `XCLocalSwiftPackageReference`).

## Configure

Edit `SwiftExample/SuprSendConstants.swift` and set your public key:

```swift
enum SuprSendConstants {
    static let publicKey: String = "SS.PUBK.…"
    static let host: String? = nil  // optional override for self-hosted collectors
    static let distinctIDKey: String = "suprsend_example_distinct_id"
}
```

The Notification Service Extension carries its own copy of the same key in
`SwiftExampleNotificationService/NotificationService.swift` — keep them in
sync. (Extension targets cannot share Swift files with the main app when
the app uses Xcode's file-system-synchronized groups.)

If you want to exercise the JWT-authenticated identify flow, point
`SuprSendTokenService.tokenBaseURL` at a backend that mints user tokens.
When the endpoint is unreachable, the example falls back to an
unauthenticated `identify(distinctID:)` call.

Open the project and pick your signing team — `DEVELOPMENT_TEAM` is left
blank so Xcode prompts you on first build.

## Build & run

Open in Xcode:

```sh
open SwiftExample.xcodeproj
```

…then pick an iOS simulator and Run. Or from the command line:

```sh
xcodebuild -project SwiftExample.xcodeproj \
  -scheme SwiftExample \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## File layout

```
SwiftExample/
├── SwiftExampleApp.swift          # @main entry, hooks AppDelegate
├── AppDelegate.swift              # SuprSend.configure, push, deeplink
├── AppRouter.swift                # Screen enum + deeplink → screen
├── RootView.swift                 # Login vs Home/Preferences/Inbox switch
├── SuprSendConstants.swift        # public key, host, storage key
├── SuprSendTokenService.swift     # JWT mint + refresh callback
├── Toast.swift                    # ToastCenter + ToastOverlay
├── Screens/
│   ├── LoginScreen.swift
│   ├── HomeScreen.swift
│   ├── InboxScreen.swift
│   └── PreferenceScreen.swift
├── Info.plist                     # URL scheme, background modes
├── SwiftExample.entitlements      # aps-environment
└── Assets.xcassets/

SwiftExampleNotificationService/   # NSE target for rich push
├── NotificationService.swift
└── Info.plist
```
