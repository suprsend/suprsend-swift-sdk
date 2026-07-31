# Events and User methods

Track events and update user profiles from your iOS Swift app using SuprSend SDK methods to trigger workflows and sync user channels and attributes.

## Trigger Events

You can trigger events from client to SuprSend using `track` method. This can be used to trigger [event-based workflows](https://docs.suprsend.com/docs/trigger-workflow#event-based-trigger).

```swift
// syntax
await SuprSend.shared.track(event: String, properties: [String: Any]?)

// example
await SuprSend.shared.track(event: "test", properties: ["name": "john doe"])
```

**Returns:** `async -> APIResponse`

## Update User Profile

**Returns:** `async -> APIResponse`

### Update User channels

Set user channel related information using following methods. Its recommended to use SuprSend's Backend SDK's to set user channels instead of Client SDK's.

```swift
await SuprSend.shared.user.addEmail(String)
await SuprSend.shared.user.removeEmail(String)

// mobile should be as per E.164 standard: https://www.twilio.com/docs/glossary/what-e164
await SuprSend.shared.user.addSMS(String)
await SuprSend.shared.user.removeSMS(String)

// mobile should be as per E.164 standard
await SuprSend.shared.user.addWhatsapp(String)
await SuprSend.shared.user.removeWhatsapp(String)
```

### Update User properties

This is the list of available user update methods:

#### Set Timezone

This method will set users timezone. Timezone value should be in [IANA timezone format](https://timeapi.io/documentation/iana-timezones).

```swift
// syntax
await SuprSend.shared.user.setTimezone(String)

// example
await SuprSend.shared.user.setTimezone("America/Bogota");
```

#### Set Language

This method will set users preferred language. Language value should be in [ISO 639-1 Alpha-2 format](https://gist.github.com/jrnk/8eb57b065ea0b098d571).

```swift
// syntax
await SuprSend.shared.user.setPreferredLanguage(String)

// example
await SuprSend.shared.user.setPreferredLanguage("en");
```

#### Set

Set is used to set the custom user property or properties. If already property is already present value will be replaced.

```swift
// syntax
await SuprSend.shared.user.set(key: String, value: String)
await SuprSend.shared.user.set(properties: [String: Any])

// example
await SuprSend.shared.user.set(key: "name", value: "John Doe");
await SuprSend.shared.user.set(properties: ["name": "John Doe", "designation": "manager"]);
```

#### Unset

This method will remove user property. To remove channel pass `$email`, `$sms`, `$whatsapp`.

```swift
// syntax
await SuprSend.shared.user.unset(key: String)
await SuprSend.shared.user.unset(keys: [String])

// example
await SuprSend.shared.user.unset(key: "wishlist");
await SuprSend.shared.user.unset(keys: ["wishlist", "$email"]);
```

#### Append

This method will add a value to the list for a given property.

```swift
// syntax
await SuprSend.shared.user.append(key: String, value: String)
await SuprSend.shared.user.append(properties: [String: Any])

// example
await SuprSend.shared.user.append(key: "wishlist", value: "iphone12");
await SuprSend.shared.user.append(properties: ["wishlist": "iphone12", "cart": "Apple airpods"]);
```

#### Remove

This method will remove a value from the list for a given property.

```swift
// syntax
await SuprSend.shared.user.remove(key: String, value: String)
await SuprSend.shared.user.remove(properties: [String: Any])

// example
await SuprSend.shared.user.remove(key: "wishlist", value: "iphone12");
await SuprSend.shared.user.remove(properties: ["wishlist": "iphone12", "cart": "Apple airpods"]);
```

#### SetOnce

This method is similar to set method but values once set cannot be updated.

```swift
// syntax
await SuprSend.shared.user.setOnce(key: String, value: String)
await SuprSend.shared.user.setOnce(properties: [String: Any])

// example
await SuprSend.shared.user.setOnce(key: "DOB", value: "1991-10-02");
await SuprSend.shared.user.setOnce(properties: ["first_login": "2021-11-02", "DOB": "1991-10-02"]);
```

#### Increment

Add the given amount to an existing user property. If the user does not already have the associated property, the amount will be added to zero. To reduce a property, provide a negative number as the value.

```swift
// syntax
await SuprSend.shared.user.increment(key: String, value: Int)
await SuprSend.shared.user.increment(properties: [String: Int])

// example
await SuprSend.shared.user.increment(key: "login_count", value: 1);
await SuprSend.shared.user.increment(properties: ["login_count": 1, "order_count": 1]);
```

> **Note**
> Keys starting with `ss_` or `$` are reserved and will be ignored.
