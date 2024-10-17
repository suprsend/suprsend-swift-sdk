//
//  Event.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 25/08/24.
//

import Foundation

/// Represents a generic property that can be encoded as a JSON value.
public typealias Property = AnyEncodable
/// Represents a dictionary of properties that can be encoded as a JSON object.
public typealias EventProperty = [String: Encodable]

/// A wrapper struct that allows encoding any type that conforms to `Encodable`.
public class AnyEncodable: NSObject, Encodable {

    private let _encode: (Encoder) throws -> Void
    /// Initializes a new `AnyEncodable` instance with a wrapped `Encodable` value.
    /// - Parameter wrapped: The `Encodable` value to wrap.
    required public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    /// Encodes the wrapped value into the given encoder.
    /// - Parameter encoder: The encoder to use for encoding.
    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

extension AnyEncodable {
    /// An empty `AnyEncodable` instance representing an empty dictionary.
    static var empty: Self { .init([String: String]()) }
}

extension EventProperty {
    /// Converts the `EventProperty` dictionary to a `Property` type.
    /// - Returns: A `Property` instance containing the converted dictionary.
    func convertToProperty() -> Property {
        .init(mapValues { AnyEncodable($0) })
    }
}

/// Represents an event in the analytics system.
struct Event: Encodable {
    /// The name of the event.
    let event: String
    /// The unique identifier for the event.
    let insertID: String
    /// The timestamp of the event.
    let time: TimeInterval
    /// The unique identifier of the user.
    let distinctID: String
    /// The properties associated with the event.
    let properties: Property

    enum CodingKeys: String, CodingKey {
        case event
        case insertID = "$insert_id"
        case time = "$time"
        case distinctID = "distinct_id"
        case properties
    }
}

/// Represents different channels for communication
enum ChannelType: String, Encodable, CodingKeyRepresentable {
    /// iOS push notification channel.
    case iOSPush = "$iospush"
    /// Push notification channel from a vendor.
    case pushVendor = "$pushvendor"
    /// Device ID channel.
    case deviceID = "$device_id"
    /// Email channel.
    case email = "$email"
    /// SMS channel.
    case sms = "$sms"
    /// WhatsApp channel.
    case whatsapp = "$whatsapp"
    /// Slack channel.
    case slack = "$slack"
    /// Microsoft Teams channel.
    case msTeams = "$ms_teams"
    /// Preferred language channel.
    case preferredLanguage = "$preferred_language"
    /// Timezone channel.
    case timezone = "$timezone"
}

/// Represents user properties that can be updated.
struct UserProperty: Encodable {
    /// A typealias for a dictionary of event types and their associated properties.
    typealias EventProperties = [EventType: Property]
    /// Represents different types of user property operations.
    enum EventType: String, Encodable, CodingKeyRepresentable {
        /// Sets the value of a user property.
        case set = "$set"
        /// Sets the value of a user property only if it hasn't been set before.
        case setOnce = "$set_once"
        /// Adds a value to an existing user property.
        case add = "$add"
        /// Appends a value to an existing user property.
        case append = "$append"
        /// Removes a value from an existing user property.
        case remove = "$remove"
        /// Unsets a user property.
        case unset = "$unset"
    }

    /// The unique identifier for the user property update.
    let insertID: String
    /// The timestamp of the user property update.
    let time: TimeInterval
    /// The unique identifier of the user.
    let distinctID: String
    /// A dictionary of event types and their associated properties.
    let eventProperties: [EventType: Property]

    /// Encodes the `UserProperty` instance into the given encoder.
    /// - Parameter encoder: The encoder to use for encoding.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.insertID, forKey: .insertID)
        try container.encode(self.time, forKey: .time)
        try container.encode(self.distinctID, forKey: .distinctID)
        try self.eventProperties.encode(to: encoder)
    }

    enum CodingKeys: String, CodingKey {
        case insertID = "$insert_id"
        case time = "$time"
        case distinctID = "distinct_id"
    }
}
