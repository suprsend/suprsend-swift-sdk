import Foundation
import Testing
@testable import SuprSend

struct UserPropertyTests {

    @Test(
        "User Property - Add Operation",
        arguments: [[UserProperty.EventType.add: Property(["name": "John Doe"])]]
    )
    func testAddOperation(properties: [UserProperty.EventType: Property]) async throws {
        let event = UserProperty(
            insertID: UUID().uuidString,
            time: Utils.shared.epochMs(),
            distinctID: UUID().uuidString,
            eventProperties: properties,
            tenantId: nil
        )
        let jsonData = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        #expect(json.keys.contains("$insert_id"))
        #expect(json.keys.contains("distinct_id"))

        let time = try #require(json["$time"] as? Int64)
        #expect(time > 1_600_000_000_000)

        #expect(json["tenant_id"] is NSNull)

        #expect(json.keys.contains("$add"))
        #expect(json["$add"] is [String: Any])
        #expect((json["$add"] as! [String: Any])["name"] as! String == "John Doe")
    }

    @Test(
        "User Email - Add Operation",
        arguments: [[ChannelType.email: Property("hello@example.com")]]
    )
    func testEmailProperty(property: ChannelProperty) async throws {
        let event = UserProperty(
            insertID: UUID().uuidString,
            time: Utils.shared.epochMs(),
            distinctID: UUID().uuidString,
            eventProperties: [.append: property.convertToProperty()],
            tenantId: "tenant-1"
        )
        let jsonData = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        Logger().info("JSON: \(json)")
        #expect(json["tenant_id"] as? String == "tenant-1")
        #expect(json.keys.contains("$append"))
        #expect(json["$append"] is [String: Any])
        #expect((json["$append"] as? [String: Any])?["$email"] as? String == "hello@example.com")
    }

    @Test("User Property - Multiple Operations Encode As Top-Level Objects")
    func testMultipleOperations() async throws {
        let event = UserProperty(
            insertID: UUID().uuidString,
            time: Utils.shared.epochMs(),
            distinctID: UUID().uuidString,
            eventProperties: [
                .set: Property(["plan": "pro"]),
                .setOnce: Property(["signup_source": "ios"]),
                .add: Property(["login_count": 1]),
                .unset: Property(["legacy_flag"]),
            ],
            tenantId: nil
        )
        let jsonData = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        #expect((json["$set"] as? [String: Any])?["plan"] as? String == "pro")
        #expect((json["$set_once"] as? [String: Any])?["signup_source"] as? String == "ios")
        #expect((json["$add"] as? [String: Any])?["login_count"] as? Int == 1)
        #expect(json["$unset"] as? [String] == ["legacy_flag"])
    }

    @Test("Channel Property - Encodes As JSON Object")
    func testChannelPropertyEncodesAsObject() async throws {
        let channels: ChannelProperty = [
            .iOSPush: "device-token",
            .deviceID: "device-id",
        ]
        let jsonData = try JSONEncoder().encode(channels.convertToProperty())
        let json = try JSONSerialization.jsonObject(with: jsonData)

        let object = try #require(json as? [String: Any])
        #expect(object["$iospush"] as? String == "device-token")
        #expect(object["$device_id"] as? String == "device-id")
    }
}
