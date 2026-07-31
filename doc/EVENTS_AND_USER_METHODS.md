# Events and User methods

### Prerequisites

- [Integration of SuprSend Swift SDK](../README.md#integration-steps)

## Trigger Events

You can trigger events from client to SuprSend using the `track` method. This can
be used to trigger
[event-based workflows](https://docs.suprsend.com/docs/trigger-workflow#event-based-trigger).

```swift
// syntax
await SuprSend.shared.track(event: String, properties: EventProperty?, tenantId: String?)

// example
await SuprSend.shared.track(event: "test", properties: ["name": "john doe"])
```

| Parameter    | Description                                                                                                                                    |
| :----------- | :----------------------------------------------------------------------------------------------------------------------------------------------- |
| `event*`     | **Required.** Name of the event.                                                                                                               |
| `properties` | Optional. Event properties used for personalisation and workflow conditions.                                                                   |
| `tenantId`   | Optional. Attributes this single event to a tenant. Defaults to the tenant set during [identify](../README.md#step-2-authenticate-user) or [changeTenant](../README.md#change-active-tenant). Passing it here does not change the session tenant. |

**Returns:** `async -> APIResponse`

> **Note**
> `EventProperty` is `[String: Encodable]`.

## Update User Profile

All the methods below return `async -> APIResponse`.

### Update User channels

Set user channel related information using the following methods. It's
recommended to use SuprSend's Backend SDKs to set user channels instead of the
Client SDKs.

```swift
await SuprSend.shared.user.addEmail(String)
await SuprSend.shared.user.removeEmail(String)

// mobile should be as per E.164 standard: https://www.twilio.com/docs/glossary/what-e164
await SuprSend.shared.user.addSMS(String)
await SuprSend.shared.user.removeSMS(String)

// mobile should be as per E.164 standard
await SuprSend.shared.user.addWhatsapp(String)
await SuprSend.shared.user.removeWhatsapp(String)

// APNs device token, usually set automatically from the push delegate
await SuprSend.shared.user.addiOSPush(String)
await SuprSend.shared.user.removeiOSPush(String)

await SuprSend.shared.user.addSlack(Encodable)
await SuprSend.shared.user.removeSlack(Encodable)

await SuprSend.shared.user.addMSTeams(Encodable)
await SuprSend.shared.user.removeMSTeams(Encodable)
```

### Update User properties

This is the list of available user update methods.

#### Set Timezone

This method will set the user's timezone. The timezone value should be in
[IANA timezone format](https://timeapi.io/documentation/iana-timezones).

```swift
// syntax
await SuprSend.shared.user.setTimezone(String)

// example
await SuprSend.shared.user.setTimezone("America/Bogota")
```

#### Set Language

This method will set the user's preferred language. The language value should be
in [ISO 639-1 Alpha-2 format](https://gist.github.com/jrnk/8eb57b065ea0b098d571).

```swift
// syntax
await SuprSend.shared.user.setPreferredLanguage(String)

// example
await SuprSend.shared.user.setPreferredLanguage("en")
```

#### Set

`set` is used to set a custom user property or properties. If the property is
already present, its value will be replaced.

```swift
// syntax
await SuprSend.shared.user.set(key: String, value: Encodable)
await SuprSend.shared.user.set(properties: EventProperty)

// example
await SuprSend.shared.user.set(key: "name", value: "John Doe")
await SuprSend.shared.user.set(properties: ["name": "John Doe", "designation": "manager"])
```

#### Unset

This method will remove a user property. To remove a channel pass `$email`,
`$sms`, `$whatsapp`.

```swift
// syntax
await SuprSend.shared.user.unset(key: String)
await SuprSend.shared.user.unset(keys: [String])

// example
await SuprSend.shared.user.unset(key: "wishlist")
await SuprSend.shared.user.unset(keys: ["wishlist", "$email"])
```

#### Append

This method will add a value to the list for a given property.

```swift
// syntax
await SuprSend.shared.user.append(key: String, value: Encodable)
await SuprSend.shared.user.append(properties: EventProperty)

// example
await SuprSend.shared.user.append(key: "wishlist", value: "iphone12")
await SuprSend.shared.user.append(properties: ["wishlist": "iphone12", "cart": "Apple airpods"])
```

#### Remove

This method will remove a value from the list for a given property.

```swift
// syntax
await SuprSend.shared.user.remove(key: String, value: Encodable)
await SuprSend.shared.user.remove(properties: EventProperty)

// example
await SuprSend.shared.user.remove(key: "wishlist", value: "iphone12")
await SuprSend.shared.user.remove(properties: ["wishlist": "iphone12", "cart": "Apple airpods"])
```

#### SetOnce

This method is similar to `set`, but values once set cannot be updated.

```swift
// syntax
await SuprSend.shared.user.setOnce(key: String, value: Encodable)
await SuprSend.shared.user.setOnce(properties: EventProperty)

// example
await SuprSend.shared.user.setOnce(key: "DOB", value: "1991-10-02")
await SuprSend.shared.user.setOnce(properties: ["first_login": "2021-11-02", "DOB": "1991-10-02"])
```

#### Increment

Add the given amount to an existing user property. If the user does not already
have the associated property, the amount will be added to zero. To reduce a
property, provide a negative number as the value.

```swift
// syntax
await SuprSend.shared.user.increment(key: String, value: Float)
await SuprSend.shared.user.increment(properties: [String: Float])

// example
await SuprSend.shared.user.increment(key: "login_count", value: 1)
await SuprSend.shared.user.increment(properties: ["login_count": 1, "order_count": 1])
```

> **Note**
> Keys starting with `ss_` or `$` are reserved and will be ignored.
