import Foundation
import Testing

@testable import SuprSend

struct ClientTests {

    @Test func identifySendsIdentifyEventOnce() async {
        let backend = MockBackend()
        let client = backend.client()
        let distinctID = "user-\(UUID().uuidString)"

        let first = await client.identify(distinctID: distinctID, tenantId: "tenant-a")
        let again = await client.identify(distinctID: distinctID)

        #expect(first.status == .success)
        #expect(again.status == .success)
        #expect(client.tenantId == "tenant-a")
        let identifies = backend.requests.compactMap(\.jsonBody).filter { $0["event"] as? String == "$identify" }
        #expect(identifies.count == 1)
        #expect(identifies.first?["distinct_id"] as? String == distinctID)
        #expect(identifies.first?["tenant_id"] as? String == "tenant-a")
    }

    @Test func identifyRejectsDifferentUserUntilReset() async {
        let backend = MockBackend { request in
            request.path.hasSuffix("/preference/") ? .json(#"{"sections":[],"channel_preferences":[]}"#) : .ok
        }
        let client = await backend.identifiedClient(tenantId: "tenant-a")
        _ = await client.user.preferences.getPreferences()
        let otherUser = "user-\(UUID().uuidString)"

        let rejected = await client.identify(distinctID: otherUser)
        #expect(rejected.error?.type == .validation)

        let reset = await client.reset(options: .init(unsubscribePush: false))
        #expect(reset.status == .success)
        #expect(client.distinctID == nil)
        #expect(client.tenantId == nil)
        #expect(client.user.preferences.data == nil)

        let accepted = await client.identify(distinctID: otherUser)
        #expect(accepted.status == .success)
        #expect(client.distinctID == otherUser)
    }

    @Test func trackRequiresIdentifyAndSendsSanitizedEvent() async throws {
        let backend = MockBackend()
        let client = backend.client()

        let anonymous = await client.track(event: "Viewed")
        #expect(anonymous.error?.type == .validation)
        #expect(backend.requests.isEmpty)

        _ = await client.identify(distinctID: "user-\(UUID().uuidString)", tenantId: "tenant-a")
        _ = await client.track(event: "Purchased", properties: ["plan": "pro", "$internal": 1, "ss_flag": true])
        _ = await client.track(event: "Shared", tenantId: "tenant-b")

        let events = backend.events
        try #require(events.count == 2)
        #expect(events[0]["event"] as? String == "Purchased")
        #expect(events[0]["properties"] as? [String: String] == ["plan": "pro"])
        #expect(events[0]["tenant_id"] as? String == "tenant-a")
        #expect(events[1]["tenant_id"] as? String == "tenant-b")
        #expect(client.tenantId == "tenant-a")
    }

    @Test func changeTenantValidatesAndSwitches() async {
        let client = SuprSendClient(publicKey: MockBackend.publicKey)

        let empty = await client.changeTenant(tenantId: "")
        #expect(empty.error?.type == .validation)
        #expect(client.tenantId == nil)

        let switched = await client.changeTenant(tenantId: "tenant-a")
        #expect(switched.status == .success)
        #expect(client.tenantId == "tenant-a")

        let moved = await client.changeTenant(tenantId: "tenant-b", pushTokenAction: .move)
        #expect(moved.status == .success)
        #expect(client.tenantId == "tenant-b")
    }

    @Test func expiringUserTokenIsRefreshedBeforeRequest() async {
        let backend = MockBackend()
        let client = backend.client()
        let refreshes = Counter()
        let freshToken = Self.unsignedJWT(expiresIn: 3600)

        let response = await client.identify(
            distinctID: "user-\(UUID().uuidString)",
            userToken: Self.unsignedJWT(expiresIn: 10),
            options: .init(refreshUserToken: { _, _ in
                refreshes.increment()
                return freshToken
            })
        )
        _ = await client.track(event: "Opened")

        #expect(response.status == .success)
        #expect(refreshes.value == 1)
        let signatures = backend.requests.map { $0.value(forHTTPHeaderField: "x-ss-signature") }
        #expect(signatures == [freshToken, freshToken])
    }

    @Test func concurrentTokenRefreshesShareOneRun() async {
        let inflight = SharedInflightTask()
        let runs = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await inflight.run {
                        runs.increment()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
        }

        #expect(runs.value == 1)
    }

    @Test func requestsCarryUserAgentHeaders() async throws {
        let backend = MockBackend()
        _ = await backend.identifiedClient(appInfo: AppInfo(name: "Acme", version: "1.2.3"))
        let request = try #require(backend.requests.first)

        #expect(request.value(forHTTPHeaderField: "Authorization") == MockBackend.publicKey)

        let userAgent = try #require(request.value(forHTTPHeaderField: "X-Suprsend-User-Agent"))
        #expect(userAgent.hasPrefix("\(Constants.sdkName)/\(Constants.sdkVersion)"))
        #expect(userAgent.contains("(Acme/1.2.3)"))

        let clientUserAgent = try #require(request.value(forHTTPHeaderField: "X-Suprsend-Client-User-Agent"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(clientUserAgent.utf8)) as? [String: Any])
        #expect(json["sdk"] as? String == Constants.sdkName)
        #expect(json["sdk_version"] as? String == Constants.sdkVersion)
        #expect((json["app_info"] as? [String: Any])?["name"] as? String == "Acme")
    }

    // The SDK only base64-decodes the payload to read `exp`, so the signature can be fake.
    private static func unsignedJWT(expiresIn seconds: TimeInterval) -> String {
        let payload = #"{"exp":\#(Int(Date().timeIntervalSince1970 + seconds))}"#
        let encoded = [#"{"alg":"none"}"#, payload].map {
            Data($0.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encoded.joined(separator: ".") + ".signature"
    }
}
