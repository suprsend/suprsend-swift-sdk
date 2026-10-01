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
    static var empty: Self { .init([String: String]()) }
}

extension EventProperty {
    func convertToProperty() -> Property {
        .init(mapValues { AnyEncodable($0) })
    }
}

struct Event: Encodable {
    let event: String
    let insertID: String
    let time: Int64
    let distinctID: String
    let properties: Property
    let tenantId: String?
    let emitsTenant: Bool

    init(
        event: String,
        insertID: String,
        time: Int64,
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
        // encode, not encodeIfPresent: a nil tenant must serialise as JSON null.
        if emitsTenant {
            try container.encode(tenantId, forKey: .tenantId)
        }
    }
}

enum ChannelType: String, Encodable {
    case iOSPush = "$iospush"
    case pushVendor = "$id_provider"
    case deviceID = "$device_id"
    case bundleID = "$bundle_id"
    case email = "$email"
    case sms = "$sms"
    case whatsapp = "$whatsapp"
    case slack = "$slack"
    case msTeams = "$ms_teams"
    case preferredLanguage = "$preferred_language"
    case timezone = "$timezone"
}

struct UserProperty: Encodable {
    typealias EventProperties = [EventType: Property]
    enum EventType: String, Encodable {
        case set = "$set"
        case setOnce = "$set_once"
        case add = "$add"
        case append = "$append"
        case remove = "$remove"
        case unset = "$unset"
    }

    let insertID: String
    let time: Int64
    let distinctID: String
    let eventProperties: [EventType: Property]
    let tenantId: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.insertID, forKey: .insertID)
        try container.encode(self.time, forKey: .time)
        try container.encode(self.distinctID, forKey: .distinctID)
        // encode, not encodeIfPresent: a nil tenant must serialise as JSON null.
        try container.encode(self.tenantId, forKey: .tenantId)
        // Per-key encode: enum-keyed Dictionary traps (EXC_BREAKPOINT) before iOS 15.4 / macOS 12.3.
        var operations = encoder.container(keyedBy: RawCodingKey.self)
        for (type, property) in eventProperties {
            try operations.encode(property, forKey: RawCodingKey(type.rawValue))
        }
    }

    enum CodingKeys: String, CodingKey {
        case insertID = "$insert_id"
        case time = "$time"
        case distinctID = "distinct_id"
        case tenantId = "tenant_id"
    }
}

struct RawCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
}
