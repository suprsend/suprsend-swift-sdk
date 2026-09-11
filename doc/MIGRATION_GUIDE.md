# Migrating to v2 from v1

v2 introduces tenant scoping across the sdk and moves preferences under `user`.

## Tenant scoping

Skip this guide if you don't use multi-tenant architecture, i.e. if you don't pass tenant id in userToken jwt payload and don't use tenant id fields for preferences and inbox.

Pass `tenantId` in `identify` and the rest of the SDK, including preferences and inbox, uses it.

The per-call `tenantId` params in v1 still work and override the global one, so you can migrate gradually or leave your v1 code as is.

```swift
// (v2)

await SuprSend.shared.identify(
  distinctID: "user-distinct-id",
  userToken: jwt,
  tenantId: "TENANT_ID"
)

// inherited — no need to repeat it in v2
await SuprSend.shared.user.preferences.getPreferences()
let feed = SuprSend.shared.feeds.initialize()
```

```swift
// (v1)

await SuprSend.shared.identify(distinctID: "user-distinct-id", userToken: jwt)

// tenant repeated at every call site
await SuprSend.shared.preferences.getPreferences(
  args: Preferences.Args(tenantId: "TENANT_ID")
)

let feed = SuprSend.shared.feeds.initialize(
  options: IFeedOptions(tenantId: "TENANT_ID")
)
```

**IMPORTANT**: Whichever tenant you pass in sdk, it must be included in `scope.tenant_id` of the [userToken](https://docs.suprsend.com/docs/client-authentication#enhanced-security-mode-with-signed-user-token), else the server throws scoping error.

## Preferences accessor

`SuprSend.shared.preferences` is removed. Use `SuprSend.shared.user.preferences`; the methods are unchanged.

```swift
// (v2)
await SuprSend.shared.user.preferences.getPreferences()

// (v1)
await SuprSend.shared.preferences.getPreferences()
```

`reset()` now also clears cached preferences data and drops pending preference updates, so call `getPreferences` again after the next `identify`.
