//
//  Event.swift
//  SuprSend
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
    /// Active tenant this event is scoped to, sourced from the global tenant.
    /// Emitted at the top level of the `v2/event` payload — `null` when no
    /// tenant is set — so the backend can attribute the event.
    let tenantId: String?
    /// Whether to emit the `tenant_id` key at all. Notification events sent via
    /// the public path (`$notification_clicked`/`_delivered`/`_dismiss`) omit
    /// it entirely — their tenant is resolved server-side from the notification
    /// id, and the client's current tenant may be stale or unrelated.
    let emitsTenant: Bool

    init(
        event: String,
        insertID: String,
        time: TimeInterval,
        distinctID: String,
        properties: Property,
        tenantId: String?,
        emitsTenant: Bool = true
    ) {
        self.event = event
        self.insertID = insertID
        self.time = time
        self.distinctID = distinctID
        self.properties = properties
        self.tenantId = tenantId
        self.emitsTenant = emitsTenant
    }

    enum CodingKeys: String, CodingKey {
        case event
        case insertID = "$insert_id"
        case time = "$time"
        case distinctID = "distinct_id"
        case properties
        case tenantId = "tenant_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(insertID, forKey: .insertID)
        try container.encode(time, forKey: .time)
        try container.encode(distinctID, forKey: .distinctID)
        try container.encode(properties, forKey: .properties)
        // Explicit `encode` (not `encodeIfPresent`) so a nil tenant serialises
        // as JSON `null` rather than being omitted. Skipped entirely when
        // `emitsTenant` is false (public notification events).
        if emitsTenant {
            try container.encode(tenantId, forKey: .tenantId)
        }
    }
}

/// Represents different channels for communication
enum ChannelType: String, Encodable, CodingKeyRepresentable {
    /// iOS push notification channel.
    case iOSPush = "$iospush"
    /// Push notification channel from a vendor.
    case pushVendor = "$id_provider"
    /// Device ID channel.
    case deviceID = "$device_id"
    /// App bundle identifier.
    case bundleID = "$bundle_id"
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
    /// Active tenant this event is scoped to, sourced from the global tenant.
    /// Always emitted at the top level of the `v2/event` payload — `null` when
    /// no tenant is set.
    let tenantId: String?

    /// Encodes the `UserProperty` instance into the given encoder.
    /// - Parameter encoder: The encoder to use for encoding.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.insertID, forKey: .insertID)
        try container.encode(self.time, forKey: .time)
        try container.encode(self.distinctID, forKey: .distinctID)
        // Explicit `encode` (not `encodeIfPresent`) so a nil tenant serialises
        // as JSON `null` rather than being omitted from the payload.
        try container.encode(self.tenantId, forKey: .tenantId)
        try self.eventProperties.encode(to: encoder)
    }

    enum CodingKeys: String, CodingKey {
        case insertID = "$insert_id"
        case time = "$time"
        case distinctID = "distinct_id"
        case tenantId = "tenant_id"
    }
}
