//
//  UserPropertyTests.swift
//  SuprSendSwiftTests
//
//  Created by Ram Suthar on 16/09/24.
//

import Testing
import OSLog
@testable import SuprSendSwift

struct UserPropertyTests {

    @Test(
        "User Property - Add Operation",
        arguments: [[UserProperty.EventType.add: Property(["name": "John Doe"])]]
    )
    func testAddOperation(properties: [UserProperty.EventType: Property]) async throws {
        let event = UserProperty(
            insertID: UUID().uuidString,
            time: Date.now.timeIntervalSince1970,
            distinctID: UUID().uuidString,
            eventProperties: properties
        )
        let jsonData = try! JSONEncoder().encode(event)
        let json = try! JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        
        #expect(json.keys.contains("$insert_id"))
        #expect(json.keys.contains("distinct_id"))
        #expect(json.keys.contains("$time"))
        
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
            time: Date.now.timeIntervalSince1970,
            distinctID: UUID().uuidString,
            eventProperties: [.append: property.convertToProperty()]
        )
        let jsonData = try! JSONEncoder().encode(event)
        let json = try! JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        Logger().info("JSON: \(json)")
        #expect(json.keys.contains("$append"))
        #expect(json["$append"] is [String: Any])
        #expect((json["$append"] as? [String: Any])?["$email"] as? String == "hello@example.com")
    }

}
