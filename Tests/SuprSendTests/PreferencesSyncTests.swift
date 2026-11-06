import Foundation
import Testing

@testable import SuprSend

struct PreferencesSyncTests {

    @Test func failedStatusWithoutErrorObjectIsAnErrorAndKeepsData() async throws {
        let host = Self.uniqueHost()
        let client = await Self.identifiedClient(host: host) { request in
            guard Self.isPreferenceFetch(request) else { return .init(statusCode: 200, body: "{}") }
            let fetches = MockURLProtocol.requests(host: host).filter(Self.isPreferenceFetch).count
            return fetches == 1
                ? .init(statusCode: 200, body: Self.seedJSON)
                : .init(statusCode: 429, body: #"{"message":"Too many requests"}"#)
        }
        let preferences = client.user.preferences

        let first = await preferences.getPreferences()
        #expect(first.status == .success)
        let loaded = try #require(preferences.data)

        let second = await preferences.getPreferences()
        #expect(second.status == .error)
        #expect(second.statusCode == 429)
        #expect(second.error?.type == .unknown)
        #expect(preferences.data === loaded)
    }

    @Test func categoryUpdateMergesReplyWithoutRefetching() async throws {
        let host = Self.uniqueHost()
        let client = await Self.identifiedClient(host: host) { request in
            switch (request.httpMethod, Self.endpoint(request)) {
            case ("PATCH", "/category/marketing/"):
                return .init(statusCode: 200, body: Self.categoryJSON("marketing", name: "Marketing (server)", preference: "opt_out"))
            case ("PATCH", "/category/newsletter/"):
                return .init(statusCode: 200, body: Self.categoryJSON("newsletter", name: "Newsletter (server)", preference: "opt_out"))
            case ("GET", "/"):
                return .init(statusCode: 200, body: Self.seedJSON)
            default:
                return .init(statusCode: 200, body: "{}")
            }
        }
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()
        let marketing = try #require(Self.category("marketing", in: preferences.data))

        let newsletterAtFirstUpdate = FirstValue<PreferenceOptions>()
        client.emitter.on(.preferencesUpdated) { response in
            newsletterAtFirstUpdate.setOnce(Self.category("newsletter", in: response?.body)?.preference)
        }

        #expect(preferences.updateCategoryPreference(category: "marketing", preference: .optOut).status == .success)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(preferences.updateCategoryPreference(category: "newsletter", preference: .optOut).status == .success)
        // Marketing is sent at ~1.0s while newsletter is still debouncing; newsletter is sent at ~1.5s.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(newsletterAtFirstUpdate.value == .optOut)
        #expect(Self.category("marketing", in: preferences.data) === marketing)
        #expect(marketing.name == "Marketing (server)")
        #expect(Self.category("newsletter", in: preferences.data)?.name == "Newsletter (server)")

        let requests = MockURLProtocol.requests(host: host)
        #expect(requests.filter(Self.isPreferenceFetch).count == 1)
        #expect(requests.filter { $0.httpMethod == "PATCH" }.count == 2)
    }

    @Test func digestUpdateReturnsServerCategoryAndMergesIt() async throws {
        let host = Self.uniqueHost()
        let client = await Self.identifiedClient(host: host) { request in
            switch (request.httpMethod, Self.endpoint(request)) {
            case ("PATCH", "/category/marketing/"):
                return .init(statusCode: 200, body: Self.categoryJSON("marketing", name: "Marketing (server)", preference: "opt_in"))
            case ("GET", "/"):
                return .init(statusCode: 200, body: Self.seedJSON)
            default:
                return .init(statusCode: 200, body: "{}")
            }
        }
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()

        let response = await preferences.updateDigestScheduleInCategory(
            category: "marketing", digestSchedule: .init(id: "weekly", time: "09:00"))

        #expect(response.status == .success)
        #expect(response.body?.category == "marketing")
        #expect(response.body?.name == "Marketing (server)")
        #expect(Self.category("marketing", in: preferences.data)?.name == "Marketing (server)")
        #expect(MockURLProtocol.requests(host: host).filter(Self.isPreferenceFetch).count == 1)
    }

    @Test func readMethodsDecodeTheirBodies() async throws {
        let host = Self.uniqueHost()
        let client = await Self.identifiedClient(host: host) { request in
            switch Self.endpoint(request) {
            case "/category/":
                return .init(
                    statusCode: 200,
                    body: #"{"meta":{"count":2,"limit":10,"offset":0},"results":["#
                        + Self.categoryJSON("marketing", name: "Marketing", preference: "opt_in") + ","
                        + Self.categoryJSON("newsletter", name: "Newsletter", preference: "opt_out") + "]}")
            case "/category/marketing/":
                return .init(statusCode: 200, body: Self.categoryJSON("marketing", name: "Marketing", preference: "opt_in"))
            case "/channel_preference/":
                return .init(statusCode: 200, body: #"{"channel_preferences":[{"channel":"email","is_restricted":true}]}"#)
            default:
                return .init(statusCode: 200, body: "{}")
            }
        }
        let preferences = client.user.preferences

        let categories = await preferences.getCategories()
        #expect(categories.body?.results.map(\.category) == ["marketing", "newsletter"])
        #expect(categories.body?.meta?.count == 2)

        let category = await preferences.getCategory(category: "marketing")
        #expect(category.body?.name == "Marketing")

        let channels = await preferences.getOverallChannelPreferences()
        #expect(channels.body?.channelPreferences?.first?.channel == "email")
        #expect(channels.body?.channelPreferences?.first?.isRestricted == true)
    }

    // MARK: - Helpers

    private static func uniqueHost() -> String {
        "mock-\(UUID().uuidString.lowercased()).test"
    }

    private static func identifiedClient(
        host: String,
        handler: @escaping MockURLProtocol.Handler
    ) async -> SuprSendClient {
        MockURLProtocol.register(host: host, handler: handler)
        let client = SuprSendClient(publicKey: "test-key", options: .init(host: "https://\(host)"))
        _ = await client.identify(distinctID: "user-\(UUID().uuidString)")
        return client
    }

    private static func endpoint(_ request: URLRequest) -> String? {
        guard let url = request.url,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path,
              let range = path.range(of: "/preference")
        else { return nil }
        return String(path[range.upperBound...])
    }

    private static func isPreferenceFetch(_ request: URLRequest) -> Bool {
        request.httpMethod == "GET" && endpoint(request) == "/"
    }

    private static func category(_ slug: String, in data: PreferenceData?) -> SuprSend.Category? {
        data?.sections?.flatMap { $0.subcategories ?? [] }.first { $0.category == slug }
    }

    private static func categoryJSON(_ slug: String, name: String, preference: String) -> String {
        """
        {"name":"\(name)","category":"\(slug)","preference":"\(preference)","is_editable":true,\
        "channels":[{"channel":"email","preference":"opt_in","is_editable":true}]}
        """
    }

    private static let seedJSON = """
        {
          "sections": [
            {
              "name": "s",
              "subcategories": [
                \(categoryJSON("marketing", name: "Marketing", preference: "opt_in")),
                \(categoryJSON("newsletter", name: "Newsletter", preference: "opt_in"))
              ]
            }
          ],
          "channel_preferences": [{"channel": "email", "is_restricted": false}]
        }
        """
}

private final class FirstValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    private var isSet = false

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func setOnce(_ value: Value?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isSet else { return }
        stored = value
        isSet = true
    }
}
