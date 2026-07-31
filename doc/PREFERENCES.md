# Preferences

### Prerequisites

- [Integration of SuprSend Swift SDK](../README.md#integration-steps)
- [Configure preference categories](https://docs.suprsend.com/docs/user-preferences#setting-up-preference-categories) on the SuprSend dashboard

> **Tip:**
> A working example can be found in
> [`Example/SwiftExample/Screens/PreferenceScreen.swift`](https://github.com/suprsend/suprsend-swift-sdk/blob/main/Example/SwiftExample/Screens/PreferenceScreen.swift).

## Understanding preference structure

This is how a typical preference page will look like:

![Full preference page structure](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/full-pref-structure.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=46051ca09456c491a19ae6ddb0c45c4b)

A preference page contains 2 sections:

1. Category-level preference settings
   - [Sections](#11-sections)
   - [Categories](#12-categories-sections---sub-categories)
   - [Category Channels](#13-category-channels-sections---sub-categories---channels)
2. [Overall channel-level preferences](#2-overall-channel-preferences)

![Category-level preference settings on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-preferences-1.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=bafabe25e611cd63e3a3b3ccce751f92)

![Overall channel-level preferences on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-preferences-2.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=fd37373b6f2f1d5ed5cd42500bc2e53d)

### Preferences data structure

```swift
public class PreferenceData: Codable {
  public let sections: [Section]?
  public let channelPreferences: [ChannelPreference]?

  enum CodingKeys: String, CodingKey {
    case sections
    case channelPreferences = "channel_preferences"
  }
}

public class Section: Codable {
  public let name: String?
  public let description: String?
  public let subcategories: [Category]?
}

public class Category: Codable {
  public let name: String
  public let category: String
  public let description: String?
  public var preference: PreferenceOptions
  public let isEditable: Bool
  public let channels: [CategoryChannel]?

  enum CodingKeys: String, CodingKey {
    case name
    case category
    case description
    case preference
    case isEditable = "is_editable"
    case channels
  }
}

public class CategoryChannel: Codable {
  public let channel: String
  public var preference: PreferenceOptions
  public let isEditable: Bool

  enum CodingKeys: String, CodingKey {
    case channel
    case preference
    case isEditable = "is_editable"
  }
}

public class ChannelPreference: Codable {
  public let channel: String
  public var isRestricted: Bool

  enum CodingKeys: String, CodingKey {
    case channel
    case isRestricted = "is_restricted"
  }
}

public enum PreferenceOptions: String, Codable {
  case optIn = "opt_in"
  case optOut = "opt_out"
}

public enum ChannelLevelPreferenceOptions: String, Codable {
  case all = "all"
  case required = "required"
}
```

<details>
<summary>Example response</summary>

```json
{
  "sections": [
    {
      "name": null,
      "subcategories": [
        {
          "name": "Payment and History",
          "category": "payment-and-history",
          "description": "Send updates related to my payment history.",
          "preference": "opt_in",
          "is_editable": false,
          "channels": [
            {
              "channel": "androidpush",
              "preference": "opt_in",
              "is_editable": true
            },
            {
              "channel": "email",
              "preference": "opt_in",
              "is_editable": false
            }
          ]
        }
      ]
    },
    {
      "name": "Product Updates",
      "description": "Non-marketing notifications related to authentication, activity updates, reminders etc.",
      "subcategories": [
        {
          "name": "Newsletter",
          "category": "newsletter",
          "description": "Send updates on new feature in the product",
          "preference": "opt_in",
          "is_editable": true,
          "channels": [
            {
              "channel": "androidpush",
              "preference": "opt_in",
              "is_editable": true
            },
            {
              "channel": "email",
              "preference": "opt_out",
              "is_editable": false
            }
          ]
        }
      ]
    }
  ],
  "channel_preferences": [
    {
      "channel": "androidpush",
      "is_restricted": false
    },
    {
      "channel": "email",
      "is_restricted": true
    }
  ]
}
```

</details>

### 1.1 Sections

This contains the name, description, and subcategories. Loop through the sections
list and, for every section item, if a name and description are present show the
heading; if a subcategories list is present, loop through it and show all
subcategories under that section heading.

Subcategories can exist without sections, as the section is an optional field. In
that case the section's name will not be available. For sections where the name
is not present, you can directly show its subcategories list without showing a
heading for the section in the UI.

![Preference sections on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-sections.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=ed2462d6b94cea40d797de056896509a)

```swift
public class Section: Codable {
  public let name: String?
  public let description: String?
  public let subcategories: [Category]?
}
```

| Property        | Description                                               |
| --------------- | --------------------------------------------------------- |
| `name`          | name of the section                                       |
| `description`   | description of the section                                |
| `subcategories` | data of all sub-categories to be shown inside the section |

### 1.2 Categories (sections -> sub-categories)

This is the place where the user sets their category-level preferences. While
looping through the subcategories list, for every subcategory item show the name
and description in the UI.

![Preference categories on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-category.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=286bb93a230fccaa45ab9d9f0acd5eb8)

```swift
public class Category: Codable {
  public let name: String
  public let category: String
  public let description: String?
  public var preference: PreferenceOptions
  public let isEditable: Bool
  public let channels: [CategoryChannel]?

  enum CodingKeys: String, CodingKey {
    case name
    case category
    case description
    case preference
    case isEditable = "is_editable"
    case channels
  }
}
```

| Property      | Description                                                                                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `category`    | This key is the id of the category which is used while updating the preference.                                                                    |
| `name`        | name of the category to be shown on the UI                                                                                                         |
| `description` | description of the category to be shown on the UI                                                                                                  |
| `preference`  | This key indicates if the category's preference switch is on or off. Get **optIn** when the switch is on and **optOut** when the switch is off.     |
| `isEditable`  | Indicates if the preference switch button is disabled or not. If its value is `false` then the preference setting for that category can't be edited. |
| `channels`    | data of all category channels to be shown below the sub-category. Loop through it to show checkboxes under every subcategory item.                  |

### 1.3 Category channels (sections -> sub-categories -> channels)

This contains a list of channels, the channel preference status and whether it's
editable or not. While looping through the subcategory list, for every subcategory
item loop through its channels list and for every channel show a channel-level
checkbox.

![Category channels on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-category-channels.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=489568f7581a820518898ee90300df01)

```swift
public class CategoryChannel: Codable {
  public let channel: String
  public var preference: PreferenceOptions
  public let isEditable: Bool

  enum CodingKeys: String, CodingKey {
    case channel
    case preference
    case isEditable = "is_editable"
  }
}
```

| Property     | Description                                                                                                                                 |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `channel`    | name of the channel to be shown on UI. The same key will be used as id of the channel while updating the preference.                        |
| `preference` | This key indicates if the channel's preference switch is on or off. Get **optIn** when the switch is on and **optOut** when the switch is off. |
| `isEditable` | Indicates if the preference checkbox is disabled or not. If its value is `false` then the preference setting for that channel can't be edited. |

### 2. Overall channel preferences

It's a list of all channel-level preferences. Loop through the list and for each
item show the UI as given in the below image.

![Overall channel preferences on mobile](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-preferences-2.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=fd37373b6f2f1d5ed5cd42500bc2e53d)

```swift
public class ChannelPreference: Codable {
  public let channel: String
  public var isRestricted: Bool

  enum CodingKeys: String, CodingKey {
    case channel
    case isRestricted = "is_restricted"
  }
}
```

| Property       | Description                                                                                                                                                                                                                                                                                  |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `channel`      | name of the channel to be shown on UI. The same key will be used as id of the channel while updating the preference.                                                                                                                                                                         |
| `isRestricted` | This key indicates the restriction level of the channel. If restricted, notifications will only be sent in the category where this channel is added as mandatory in preference category settings. **true** means the Required radio button is selected. **false** means All is selected. |

## Integration

> **Note**
> All the methods below are on the same `Preferences` instance and the update
> methods act on the data cached by `getPreferences`. Use one instance
> consistently — `SuprSend.shared.preferences` and
> `SuprSend.shared.user.preferences` are separate instances with separate
> caches, so calling `getPreferences` on one and updating on the other returns a
> validation error.

### Get preferences data

Use this method to get preferences data and create the preferences UI by
following the above sections. This method should be called first, before any
update preference methods.

```swift
await SuprSend.shared.preferences.getPreferences(
  args: Preferences.Args(tenantId: "tenant-id", tags: .string("tag"), locale: "es")
)
```

| Argument (optional)  | Description                                                                                                                                                                                                                                                                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tenantId`           | Tenant identifier for loading per-tenant preferences. Defaults to the tenant set on the client during [identify](../README.md#step-2-authenticate-user) or [changeTenant](../README.md#change-active-tenant).                                                                                                                                                            |
| `showOptOutChannels` | Whether opted-out channels are included in the response. Defaults to `true`.                                                                                                                                                                                                                                                                                            |
| `tags`               | Filter categories by tags — `.string(String)` or `.dictionary([String: Any])`. Used to filter preference categories based on the user's roles, department or teams (see [Tags](https://docs.suprsend.com/docs/notification-category#tags)).                                                                                                                              |
| `locale`             | Locale code (for example, `es`, `fr`, `de`, `es-AR`) to fetch preference translations in the user's locale. When provided, category names and descriptions will be returned in the specified locale. If a translation is missing for the requested locale, the system falls back in this order: `locale-region` (e.g. `es-AR`) → `locale` (e.g. `es`) → `en` (always available). |

**Returns:** `async -> PreferenceAPIResponse`

### Update channel preference in category

Calling this method will opt-in/opt-out the user from that category-level
channel. When the category's channel checkbox is editable and the user clicks on
the checkbox you can call this method.

```swift
await SuprSend.shared.preferences.updateChannelPreferenceInCategory(
  channel: "channel",
  preference: PreferenceOptions,
  category: "category"
)

public enum PreferenceOptions: String, Codable {
  case optIn = "opt_in"
  case optOut = "opt_out"
}
```

**Returns:** `async -> PreferenceAPIResponse`

![Update channel preference in category](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-update-channel-preference-in-category.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=29a092367c0a467a152bc6fd6bb0421e)

### Update category preference

This is the category-level preference changing method. Calling this method will
opt-in/opt-out the user from that category. When the category is editable and the
switch is toggled you can call this method.

```swift
SuprSend.shared.preferences.updateCategoryPreference(
  category: "category_value",
  preference: PreferenceOptions
)
```

**Returns:** `PreferenceAPIResponse` (returns the optimistic result synchronously;
the network call happens in the background — listen to the
[event listeners](#event-listeners) for the API result)

### Update overall channel preference

This method updates the channel-level preference of the user.

```swift
SuprSend.shared.preferences.updateOverallChannelPreference(
  channel: "channel",
  preference: ChannelLevelPreferenceOptions
)

public enum ChannelLevelPreferenceOptions: String, Codable {
  case all = "all"
  case required = "required"
}
```

**Returns:** `PreferenceAPIResponse` (optimistic; see
[event listeners](#event-listeners))

![Update overall channel preference](https://mintcdn.com/suprsend/ysJyO3LOXwZ5L098/images/docs/mobile-overall-update-channels.png?fit=max&auto=format&n=ysJyO3LOXwZ5L098&q=85&s=43fae7ed01bbb0ddde7ca1ae7fe425f4)

### Event listeners

All preference update APIs are optimistic updates. The actual API call happens in
the background with a 1 second debounce. Since it's a background task, the SDK
provides event listeners to get updated preference data based on the API call
status. Listen to these event listeners and update the UI accordingly.

```swift
SuprSend.shared.emitter.on(.preferencesUpdated) { response in
  // update local store so that UI is updated with latest data
}

SuprSend.shared.emitter.on(.preferencesError) { response in
  // show error toast to user
}
```

### Other methods

```swift
// Paginated list of categories, without sections.
await SuprSend.shared.preferences.getCategories(args: Preferences.CategoryArgs(limit: 20, offset: 0))

// A single category by its id.
await SuprSend.shared.preferences.getCategory(category: "category_value")

// Only the overall channel-level preferences.
await SuprSend.shared.preferences.getOverallChannelPreferences()
```
