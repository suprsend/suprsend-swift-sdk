import Foundation

public enum PreferenceOptions: String, Codable {
    /// Option to opt in for a preference
    case optIn = "opt_in"

    /// Option to opt out for a preference
    case optOut = "opt_out"
}

public enum ChannelLevelPreferenceOptions: String, Codable {
    /// All channels are allowed
    case all = "all"

    /// Only required channels are allowed
    case required = "required"
}

/// Tags filter used when fetching/updating preferences.
///
/// Mirrors the web SDK's `tags: string | Dictionary` shape — pass either a
/// raw string or a dictionary that is serialised to JSON when sent as a
/// query parameter.
public enum PreferenceTags {
    case string(String)
    case dictionary([String: Any])
}

public class CategoryChannel: Codable {
    /// The name of the channel
    public let channel: String

    /// The preference for this category
    public var preference: PreferenceOptions

    /// Whether this category is editable or not
    public let isEditable: Bool
    
    enum CodingKeys: String, CodingKey {
        case channel
        case preference
        case isEditable = "is_editable"
    }
}

public class Category: Codable {
    /// The name of the category
    public let name: String

    /// The category itself
    public let category: String

    /// A brief description of the category (optional)
    public let description: String?

    /// The preference for this category
    public var preference: PreferenceOptions
    
    /// Whether this category is editable or not
    public let isEditable: Bool

    /// An array of subcategories (optional)
    public let channels: [CategoryChannel]?

    /// Digest schedule configured for this category (optional)
    public let digestSchedule: CategoryDigestSchedule?

    /// Custom property configured for this category (optional)
    public let properties: CategoryProperties?

    enum CodingKeys: String, CodingKey {
        case name
        case category
        case description
        case preference
        case isEditable = "is_editable"
        case channels
        case digestSchedule = "digest_schedule"
        case properties
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        preference = try container.decode(PreferenceOptions.self, forKey: .preference)
        isEditable = try container.decode(Bool.self, forKey: .isEditable)
        channels = try container.decodeIfPresent([CategoryChannel].self, forKey: .channels)
        // Lenient: an unexpected shape for these newer fields must not fail the whole preferences response.
        digestSchedule = try? container.decodeIfPresent(CategoryDigestSchedule.self, forKey: .digestSchedule)
        properties = try? container.decodeIfPresent(CategoryProperties.self, forKey: .properties)
    }
}

public enum DigestFrequency: String, Codable {
    case instantly, minutely, hourly, daily, weekly, monthly
    case weeklyMondayToFriday = "weekly_mo2fr"
}

public enum WeekDay: String, Codable {
    case sunday = "su", monday = "mo", tuesday = "tu", wednesday = "we"
    case thursday = "th", friday = "fr", saturday = "sa"
}

public enum EditPolicy: String, Codable {
    case locked, editable
}

public struct MonthDay: Codable, Equatable {
    /// 1-based position in the month; negative counts from the end
    public let pos: Int

    /// Weekdays the position applies to (optional)
    public let day: [WeekDay]?

    public init(pos: Int, day: [WeekDay]? = nil) {
        self.pos = pos
        self.day = day
    }
}

/// One editable field of a digest schedule: its default, the user's value, and whether it can be changed.
public struct DigestScheduleField<Value: Codable>: Codable {
    public let editPolicy: EditPolicy?
    public let defaultValue: Value
    public let value: Value?

    enum CodingKeys: String, CodingKey {
        case editPolicy = "edit_policy"
        case defaultValue = "default_value"
        case value
    }
}

public struct CategoryDigestSchedule: Codable {
    public let id: String
    public let label: String
    public let frequency: DigestFrequency
    public let interval: Int
    public let weekdays: DigestScheduleField<[WeekDay]>?
    public let monthdays: DigestScheduleField<[MonthDay]>?
    public let time: DigestScheduleField<String>?
    public let dtstart: DigestScheduleField<String>?
    public let isDefault: Bool
    public let isUserSelected: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, frequency, interval, weekdays, monthdays, time, dtstart
        case isDefault = "is_default"
        case isUserSelected = "is_user_selected"
    }
}

public enum PropertyValueType: String, Codable {
    case integer, string
    case stringChoice = "string_choice"
    case listChoice = "list_choice"
    case stringDynamic = "string_dynamic"
    case listDynamic = "list_dynamic"
}

/// A category property value: a string, a number, or a list of strings.
public enum PropertyValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case list([String])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String].self) {
            self = .list(value)
        } else {
            throw DecodingError.typeMismatch(
                PropertyValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a string, number or list of strings"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        }
    }
}

public struct ChoiceItem: Codable {
    public let label: String
    public let value: PropertyValue
}

public struct CategoryProperties: Codable {
    public let key: String
    public let value: PropertyValue?
    public let label: String
    public let editPolicy: EditPolicy
    public let isOptional: Bool
    public let isOverridden: Bool
    public let valueType: PropertyValueType
    public let dynamicChoicesKey: String?
    public let defaultValue: PropertyValue
    public let choices: [ChoiceItem]?

    enum CodingKeys: String, CodingKey {
        case key, value, label, choices
        case editPolicy = "edit_policy"
        case isOptional = "is_optional"
        case isOverridden = "is_overridden"
        case valueType = "value_type"
        case dynamicChoicesKey = "dynamic_choices_key"
        case defaultValue = "default_value"
    }
}

public class Section: Codable {
    /// The name of the section (optional)
    public let name: String?

    /// A brief description of the section (optional)
    public let description: String?

    /// An array of categories within this section (optional)
    public let subcategories: [Category]?
}

public class ChannelPreference: Codable {
    /// The name of the channel
    public let channel: String

    /// Whether this channel is restricted or not
    public var isRestricted: Bool
    
    enum CodingKeys: String, CodingKey {
        case channel
        case isRestricted = "is_restricted"
    }
}

public class PreferenceData: Codable {
    /// An array of sections within this preference data (optional)
    public let sections: [Section]?

    /// An array of channel preferences (optional)
    public let channelPreferences: [ChannelPreference]?
    
    enum CodingKeys: String, CodingKey {
        case sections
        case channelPreferences = "channel_preferences"
    }
}

public struct PreferenceAPIResponse: Response {
    /// The status of the API response
    public let status: ResponseStatus

    /// The HTTP status code of the API response (optional)
    public let statusCode: StatusCode?

    /// The body of the API response (optional)
    public let body: PreferenceData?

    /// An error message if any (optional)
    public let error: ResponseError?

    /// Initializes a `PreferenceAPIResponse` instance
    ///
    /// - Parameters:
    ///   - status: The status of the API response.
    ///   - statusCode: The HTTP status code of the API response (optional).
    ///   - body: The body of the API response (optional).
    ///   - error: An error message if any (optional).
    public init(
        status: ResponseStatus, statusCode: StatusCode?, body: PreferenceData?,
        error: ResponseError?
    ) {
        self.status = status
        self.statusCode = statusCode
        self.body = body
        self.error = error
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(ResponseStatus.self, forKey: .status) ?? .success
        self.statusCode = try container.decodeIfPresent(StatusCode.self, forKey: .statusCode)
        self.error = try container.decodeIfPresent(ResponseError.self, forKey: .error)
        
        self.body = try PreferenceData(from: decoder)
    }
}

struct RequestPayload: Codable {
    let preference: PreferenceOptions

    let optOutChannels: [String]?

    enum CodingKeys: String, CodingKey {
        case preference

        case optOutChannels = "opt_out_channels"
    }
}

/// Digest schedule fields to apply to a category. Omitted fields are left unchanged.
public struct UpdateCategoryDigestSchedulePayload: Encodable {
    public let id: String
    public let time: String?
    public let dtstart: String?
    public let weekdays: [WeekDay]?
    public let monthdays: [MonthDay]?

    public init(
        id: String,
        time: String? = nil,
        dtstart: String? = nil,
        weekdays: [WeekDay]? = nil,
        monthdays: [MonthDay]? = nil
    ) {
        self.id = id
        self.time = time
        self.dtstart = dtstart
        self.weekdays = weekdays
        self.monthdays = monthdays
    }
}

/// A category property value to apply, keyed by ``CategoryProperties/key``.
public struct UpdateCategoryPropertyPayload: Encodable {
    public let key: String
    public let value: PropertyValue

    public init(key: String, value: PropertyValue) {
        self.key = key
        self.value = value
    }
}

struct DigestScheduleRequestPayload: Encodable {
    let digestSchedule: UpdateCategoryDigestSchedulePayload
    let preference: PreferenceOptions

    enum CodingKeys: String, CodingKey {
        case digestSchedule = "digest_schedule"
        case preference
    }
}

struct PropertiesRequestPayload: Encodable {
    let properties: [UpdateCategoryPropertyPayload]
    let preference: PreferenceOptions
}

struct ChannelRequestPayload: Codable {
    public let channelPreferences: [ChannelPreference]
    
    enum CodingKeys: String, CodingKey {
        
        case channelPreferences = "channel_preferences"
    }
}
