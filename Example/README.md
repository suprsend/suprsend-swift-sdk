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

Copy the template to `Secrets.plist` in the same folder and fill in your
public key:

```sh
cp SwiftExample/Secrets.example.plist SwiftExample/Secrets.plist
```

```xml
<key>publicKey</key>
<string>SS.PUBK.…</string>
<key>host</key>
<string></string>              <!-- optional override for self-hosted collectors -->
<key>tokenBaseURL</key>
<string></string>              <!-- backend that mints JWT user tokens -->
<key>feedAPIHost</key>
<string></string>
<key>feedSocketHost</key>
<string></string>
```

`Secrets.plist` is gitignored, so your keys and staging hosts stay out of
commits and the checked-in sources never need editing. Any value left empty
falls back to the SDK's built-in default. `SwiftExample/SuprSendConstants.swift`
just reads this plist at launch; if the file is missing, the app builds and runs
with every value at its default.

The inbox feed does **not** route through `host` — it has its own REST and
socket endpoints, passed to the SDK as `FeedHost` on `IFeedOptions`. So
overriding `host` alone still leaves the feed on its default endpoints; set
`feedAPIHost` / `feedSocketHost` too when testing against a non-production
stack.

`SuprSendConstants.swift` also defines `StorageKeys` — the `UserDefaults` keys
backing the example's login state. That's internal plumbing; you don't need to
touch it.

The Notification Service Extension does not read the plist. If you want to test
rich push, set `publicKey` and `host` directly in `NSEConstants` in
`SwiftExampleNotificationService/NotificationService.swift`, and take care not
to commit them. (Extension targets cannot share Swift files with the main app
when the app uses Xcode's file-system-synchronized groups.)

If you want to exercise the JWT-authenticated identify flow, point
`SuprSendConstants.tokenBaseURL` at a backend that mints user tokens. While
it's blank, or when the endpoint is unreachable, the example falls back to an
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
├── SuprSendConstants.swift        # reads Secrets.plist, storage keys
├── Secrets.example.plist          # template — copy to Secrets.plist
├── Secrets.plist                  # your keys & hosts (gitignored)
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
