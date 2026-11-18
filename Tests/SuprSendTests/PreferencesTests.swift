import Foundation
import Testing

@testable import SuprSend

struct PreferencesTests {

    @Test func getPreferencesLoadsDataAndKeepsItWhenRefetchFails() async throws {
        let fetches = Counter()
        let backend = MockBackend { request in
            guard Self.isPreferenceFetch(request) else { return .ok }
            return fetches.increment() == 1
                ? .json(Self.seedJSON)
                : .init(statusCode: 429, body: #"{"message":"Too many requests"}"#)
        }
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences

        let first = await preferences.getPreferences()
        #expect(first.status == .success)
        let loaded = try #require(preferences.data)
        let marketing = try #require(Self.category("marketing", in: loaded))
        #expect(marketing.digestSchedule?.weekdays?.value == [.monday, .friday])
        #expect(marketing.digestSchedule?.time?.editPolicy == .editable)
        #expect(marketing.properties?.value == .string("us"))
        #expect(marketing.properties?.choices?.count == 2)

        let second = await preferences.getPreferences()
        #expect(second.status == .error)
        #expect(second.statusCode == 429)
        #expect(preferences.data === loaded)
    }

    @Test func rapidCategoryUpdatesAreDebouncedIntoOnePatch() async throws {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()
        let newsletter = try #require(Self.category("newsletter", in: preferences.data))
        let updates = Counter()
        client.emitter.on(.preferencesUpdated) { _ in updates.increment() }

        #expect(preferences.updateCategoryPreference(category: "newsletter", preference: .optOut).status == .success)
        #expect(newsletter.preference == .optOut)
        #expect(preferences.updateCategoryPreference(category: "newsletter", preference: .optIn).status == .success)
        #expect(newsletter.preference == .optIn)

        // Debounce is 1s.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let patches = backend.requests.filter { $0.httpMethod == "PATCH" }
        #expect(patches.count == 1)
        #expect(patches.first?.jsonBody?["preference"] as? String == "opt_in")
        #expect(Self.category("newsletter", in: preferences.data) === newsletter)
        #expect(newsletter.name == "newsletter (server)")
        #expect(backend.requests.filter(Self.isPreferenceFetch).count == 1)
        #expect(updates.value == 1)
    }

    @Test func channelUpdatesApplyLocallyAndSync() async throws {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()
        let data = try #require(preferences.data)
        let marketing = try #require(Self.category("marketing", in: data))

        let inCategory = preferences.updateChannelPreferenceInCategory(
            channel: "email", preference: .optOut, category: "marketing")
        let overall = preferences.updateOverallChannelPreference(channel: "email", preference: .required)

        #expect(inCategory.status == .success)
        #expect(overall.status == .success)
        #expect(marketing.channels?.first?.preference == .optOut)
        #expect(data.channelPreferences?.first?.isRestricted == true)

        try await Task.sleep(nanoseconds: 1_500_000_000)

        let patches = backend.requests.filter { $0.httpMethod == "PATCH" }
        #expect(patches.count == 2)
        let categoryPatch = patches.first { Self.endpoint($0) == "/category/marketing/" }
        #expect(categoryPatch?.jsonBody?["opt_out_channels"] as? [String] == ["email"])
        let channelPatch = patches.first { Self.endpoint($0) == "/channel_preference/" }
        let sent = channelPatch?.jsonBody?["channel_preferences"] as? [[String: Any]]
        #expect(sent?.first?["channel"] as? String == "email")
        #expect(sent?.first?["is_restricted"] as? Bool == true)
    }

    @Test func digestAndPropertiesUpdatesSendImmediatelyAndMerge() async throws {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()
        let marketing = try #require(Self.category("marketing", in: preferences.data))

        let digest = await preferences.updateDigestScheduleInCategory(
            category: "marketing", digestSchedule: .init(id: "weekly", time: "09:00", weekdays: [.monday]))
        let properties = await preferences.updatePropertiesInCategory(
            category: "marketing", properties: [.init(key: "region", value: .string("eu"))])

        #expect(digest.status == .success)
        #expect(digest.body?.name == "marketing (server)")
        #expect(properties.status == .success)
        #expect(marketing.name == "marketing (server)")
        #expect(backend.requests.filter(Self.isPreferenceFetch).count == 1)

        let bodies = backend.requests.filter { $0.httpMethod == "PATCH" }.compactMap(\.jsonBody)
        try #require(bodies.count == 2)
        let schedule = bodies[0]["digest_schedule"] as? [String: Any]
        #expect(schedule?["id"] as? String == "weekly")
        #expect(schedule?["time"] as? String == "09:00")
        #expect(schedule?["weekdays"] as? [String] == ["mo"])
        #expect(schedule?["dtstart"] == nil)
        let sent = bodies[1]["properties"] as? [[String: Any]]
        #expect(sent?.first?["key"] as? String == "region")
        #expect(sent?.first?["value"] as? String == "eu")
    }

    @Test func updatesValidateInput() async {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences

        let beforeFetch = preferences.updateCategoryPreference(category: "marketing", preference: .optOut)
        #expect(beforeFetch.error?.message == "Call getPreferences method before performing action")

        _ = await preferences.getPreferences()
        let sentBefore = backend.requests.count

        let emptyCategory = preferences.updateCategoryPreference(category: "", preference: .optOut)
        let emptyChannel = preferences.updateOverallChannelPreference(channel: "", preference: .all)
        let unknownCategory = await preferences.updateDigestScheduleInCategory(
            category: "missing", digestSchedule: .init(id: "daily"))

        #expect(emptyCategory.error?.message == "Category parameter is missing")
        #expect(emptyChannel.error?.message == "Channel parameter is missing")
        #expect(unknownCategory.error?.message == "Category not found")
        #expect(unknownCategory.error?.type == .validation)
        #expect(backend.requests.count == sentBefore)
    }

    @Test func resetCancelsPendingUpdatesAndClearsData() async throws {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient()
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()

        #expect(preferences.updateCategoryPreference(category: "newsletter", preference: .optOut).status == .success)
        preferences.reset()

        #expect(preferences.data == nil)
        #expect(preferences.preferenceArgs == nil)
        #expect(preferences.updateCategoryPreference(category: "newsletter", preference: .optOut).error?.type == .validation)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(backend.requests.filter { $0.httpMethod == "PATCH" }.isEmpty)
    }

    @Test func fetchedTenantIsPinnedForUpdates() async throws {
        let backend = MockBackend(handler: Self.server)
        let client = await backend.identifiedClient(tenantId: "tenant-a")
        let preferences = client.user.preferences
        _ = await preferences.getPreferences()

        _ = await client.changeTenant(tenantId: "tenant-b")
        _ = await preferences.updateDigestScheduleInCategory(category: "marketing", digestSchedule: .init(id: "weekly"))

        let fetch = try #require(backend.requests.first(where: Self.isPreferenceFetch))
        let patch = try #require(backend.requests.first { $0.httpMethod == "PATCH" })
        #expect(fetch.queryValue("tenant_id") == "tenant-a")
        #expect(patch.queryValue("tenant_id") == "tenant-a")
    }

    @Test func readMethodsDecodeTheirBodies() async {
        let backend = MockBackend { request in
            switch Self.endpoint(request) {
            case "/category/":
                return .json(
                    #"{"meta":{"count":2,"limit":10,"offset":0},"results":["#
                        + Self.categoryJSON("marketing", name: "Marketing", preference: "opt_in") + ","
                        + Self.categoryJSON("newsletter", name: "Newsletter", preference: "opt_out") + "]}")
            case "/category/marketing/":
                return .json(Self.categoryJSON("marketing", name: "Marketing", preference: "opt_in"))
            case "/channel_preference/":
                return .json(#"{"channel_preferences":[{"channel":"email","is_restricted":true}]}"#)
            default:
                return .ok
            }
        }
        let client = await backend.identifiedClient()
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

    // Serves the seed on fetch and echoes the requested preference back on category updates.
    private static func server(_ request: URLRequest) -> MockURLProtocol.Stub {
        switch (request.httpMethod, endpoint(request)) {
        case ("GET", "/"):
            return .json(seedJSON)
        case ("PATCH", let path?) where path.hasPrefix("/category/"):
            let slug = String(path.split(separator: "/")[1])
            let preference = request.jsonBody?["preference"] as? String ?? "opt_in"
            return .json(categoryJSON(slug, name: "\(slug) (server)", preference: preference))
        default:
            return .ok
        }
    }

    private static func endpoint(_ request: URLRequest) -> String? {
        guard let range = request.path.range(of: "/preference") else { return nil }
        return String(request.path[range.upperBound...])
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

    private static let marketingJSON = """
        {
          "name": "Marketing",
          "category": "marketing",
          "preference": "opt_in",
          "is_editable": true,
          "channels": [{"channel": "email", "preference": "opt_in", "is_editable": true}],
          "digest_schedule": {
            "id": "weekly",
            "label": "Weekly",
            "frequency": "weekly",
            "interval": 1,
            "weekdays": {"edit_policy": "editable", "default_value": ["mo"], "value": ["mo", "fr"]},
            "time": {"edit_policy": "editable", "default_value": "09:00", "value": "10:30"},
            "is_default": false,
            "is_user_selected": true
          },
          "properties": {
            "key": "region",
            "value": "us",
            "label": "Region",
            "edit_policy": "editable",
            "is_optional": false,
            "is_overridden": true,
            "value_type": "string_choice",
            "default_value": "eu",
            "choices": [{"label": "US", "value": "us"}, {"label": "EU", "value": "eu"}]
          }
        }
        """

    private static let seedJSON = """
        {
          "sections": [
            {
              "name": "s",
              "subcategories": [
                \(marketingJSON),
                \(categoryJSON("newsletter", name: "Newsletter", preference: "opt_in"))
              ]
            }
          ],
          "channel_preferences": [{"channel": "email", "is_restricted": false}]
        }
        """
}
