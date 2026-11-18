import Foundation
import Testing

@testable import SuprSend

struct UserTests {

    @Test func propertyMethodsSendTheirOperators() async throws {
        let backend = MockBackend()
        let user = await backend.identifiedClient(tenantId: "tenant-a").user

        _ = await user.set(key: "plan", value: "pro")
        _ = await user.setOnce(key: "signup", value: "ios")
        _ = await user.increment(key: "logins", value: 1)
        _ = await user.append(key: "tags", value: "a")
        _ = await user.remove(key: "tags", value: "b")
        _ = await user.unset(key: "legacy")

        let events = backend.events
        try #require(events.count == 6)
        #expect(events[0]["$set"] as? [String: String] == ["plan": "pro"])
        #expect(events[1]["$set_once"] as? [String: String] == ["signup": "ios"])
        #expect(events[2]["$add"] as? [String: Double] == ["logins": 1])
        #expect(events[3]["$append"] as? [String: String] == ["tags": "a"])
        #expect(events[4]["$remove"] as? [String: String] == ["tags": "b"])
        #expect(events[5]["$unset"] as? [String] == ["legacy"])
        #expect(events.allSatisfy { $0["tenant_id"] as? String == "tenant-a" })
    }

    @Test func reservedKeysAreDropped() async throws {
        let backend = MockBackend()
        let user = await backend.identifiedClient().user

        _ = await user.set(properties: ["name": "Ada", "$email": "ada@example.com", "ss_internal": 1])
        _ = await user.unset(keys: ["$email", "ss_internal", "name"])

        let events = backend.events
        try #require(events.count == 2)
        #expect(events[0]["$set"] as? [String: String] == ["name": "Ada"])
        #expect(events[1]["$unset"] as? [String] == ["name"])
    }

    @Test func channelMethodsValidateBeforeSending() async {
        let backend = MockBackend()
        let user = await backend.identifiedClient().user
        let sentBefore = backend.requests.count

        let email = await user.addEmail("not-an-email")
        let sms = await user.addSMS("14151231234")
        let whatsapp = await user.addWhatsapp("+0123")

        #expect(email.error?.type == .validation)
        #expect(sms.error?.type == .validation)
        #expect(whatsapp.error?.type == .validation)
        #expect(backend.requests.count == sentBefore)
    }

    @Test func channelMethodsSendChannelKeys() async throws {
        let backend = MockBackend()
        let user = await backend.identifiedClient().user

        _ = await user.addEmail("ada@example.com")
        _ = await user.removeSMS("+14151231234")
        _ = await user.addiOSPush("device-token")
        _ = await user.setPreferredLanguage("en")

        let events = backend.events
        try #require(events.count == 4)
        #expect(events[0]["$append"] as? [String: String] == ["$email": "ada@example.com"])
        #expect(events[1]["$remove"] as? [String: String] == ["$sms": "+14151231234"])
        #expect(events[3]["$set"] as? [String: String] == ["$preferred_language": "en"])

        // Must be a JSON object; enum-keyed dictionaries encode as arrays before iOS 15.4.
        let push = try #require(events[2]["$append"] as? [String: Any])
        #expect(push["$iospush"] as? String == "device-token")
        #expect(push["$id_provider"] as? String == "apns")
        #expect(push["$device_id"] is String)
    }
}
