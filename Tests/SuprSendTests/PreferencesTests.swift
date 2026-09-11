import Foundation
import Testing

@testable import SuprSend

struct PreferencesTests {

    @Test func resetClearsCachedDataAndArgs() async throws {
        let client = try await seededClient()
        let preferences = client.user.preferences

        #expect(preferences.data != nil)
        #expect(preferences.preferenceArgs?.tenantId == "tenant-a")

        preferences.reset()

        #expect(preferences.data == nil)
        #expect(preferences.preferenceArgs == nil)

        let response = preferences.updateCategoryPreference(category: "marketing", preference: .optOut)
        #expect(response.status == .error)
        #expect(response.error?.type == .validation)
    }

    @Test func clientResetClearsPreferences() async throws {
        let client = try await seededClient()

        let response = await client.reset(options: .init(unsubscribePush: false))

        #expect(response.status == .success)
        #expect(client.distinctID == nil)
        #expect(client.user.preferences.data == nil)
        #expect(client.user.preferences.preferenceArgs == nil)
    }

    @Test func resetCancelsPendingDebouncedUpdate() async throws {
        let control = try await seededClient()
        let subject = try await seededClient()
        let controlErrors = Counter()
        let subjectErrors = Counter()
        control.emitter.on(.preferencesError) { _ in controlErrors.increment() }
        subject.emitter.on(.preferencesError) { _ in subjectErrors.increment() }

        let controlUpdate = control.user.preferences.updateCategoryPreference(
            category: "marketing", preference: .optOut)
        let subjectUpdate = subject.user.preferences.updateCategoryPreference(
            category: "marketing", preference: .optOut)
        #expect(controlUpdate.status == .success)
        #expect(subjectUpdate.status == .success)

        subject.user.preferences.reset()

        // Debounce is 1s; the unauthenticated control client emits an error when it fires.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(controlErrors.value == 1)
        #expect(subjectErrors.value == 0)
    }

    @Test func getPreferencesPinsResolvedTenant() async {
        let client = SuprSendClient(publicKey: "test-key")
        _ = await client.changeTenant(tenantId: "tenant-a")

        _ = await client.user.preferences.getPreferences()
        #expect(client.user.preferences.preferenceArgs?.tenantId == "tenant-a")
        #expect(client.user.preferences.preferenceArgs?.showOptOutChannels == true)

        _ = await client.changeTenant(tenantId: "tenant-b")
        #expect(client.user.preferences.preferenceArgs?.tenantId == "tenant-a")
    }

    @Test func categoryUpdatesRequireFetchedData() async {
        let client = SuprSendClient(publicKey: "test-key")

        let digest = await client.user.preferences.updateDigestScheduleInCategory(
            category: "marketing", digestSchedule: .init(id: "daily"))
        let properties = await client.user.preferences.updatePropertiesInCategory(
            category: "marketing", properties: [.init(key: "region", value: .string("us"))])

        #expect(digest.error?.type == .validation)
        #expect(properties.error?.type == .validation)
    }

    @Test func categoryUpdatesRejectUnknownCategory() async throws {
        let client = try await seededClient()

        let digest = await client.user.preferences.updateDigestScheduleInCategory(
            category: "missing", digestSchedule: .init(id: "daily"))
        let properties = await client.user.preferences.updatePropertiesInCategory(
            category: "missing", properties: [.init(key: "region", value: .string("us"))])

        #expect(digest.error?.message == "Category not found")
        #expect(properties.error?.message == "Category not found")
    }

    @Test func categoryUpdatesSendImmediatelyAndEmitErrors() async throws {
        let client = try await seededClient()
        let errors = Counter()
        client.emitter.on(.preferencesError) { _ in errors.increment() }

        let digest = await client.user.preferences.updateDigestScheduleInCategory(
            category: "marketing", digestSchedule: .init(id: "weekly", weekdays: [.monday]))
        let properties = await client.user.preferences.updatePropertiesInCategory(
            category: "marketing", properties: [.init(key: "region", value: .string("us"))])

        // Unauthenticated, so both requests fail at the API layer without any debounce delay.
        #expect(digest.status == .error)
        #expect(properties.status == .error)
        #expect(errors.value == 2)
    }

    @Test func categoryDecodesDigestScheduleAndProperties() throws {
        let category = try decodeCategory(Self.richCategoryJSON)

        #expect(category.digestSchedule?.id == "weekly")
        #expect(category.digestSchedule?.frequency == .weekly)
        #expect(category.digestSchedule?.weekdays?.value == [.monday, .friday])
        #expect(category.digestSchedule?.weekdays?.defaultValue == [.monday])
        #expect(category.digestSchedule?.time?.editPolicy == .editable)
        #expect(category.digestSchedule?.isUserSelected == true)
        #expect(category.properties?.key == "region")
        #expect(category.properties?.valueType == .stringChoice)
        #expect(category.properties?.value == .string("us"))
        #expect(category.properties?.defaultValue == .string("eu"))
        #expect(category.properties?.choices?.count == 2)
    }

    @Test func categoryToleratesUnexpectedDigestAndPropertyShapes() throws {
        let category = try decodeCategory(
            #"{"name":"Marketing","category":"marketing","preference":"opt_in","is_editable":true,"digest_schedule":[],"properties":"n/a"}"#
        )

        #expect(category.category == "marketing")
        #expect(category.digestSchedule == nil)
        #expect(category.properties == nil)
    }

    @Test func categoryUpdatePayloadsEncodeServerKeys() throws {
        let digest = DigestScheduleRequestPayload(
            digestSchedule: .init(id: "weekly", time: "09:00", weekdays: [.monday]), preference: .optIn)
        let properties = PropertiesRequestPayload(
            properties: [.init(key: "count", value: .number(3)), .init(key: "tags", value: .list(["a"]))],
            preference: .optOut)

        let digestJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(digest)) as? [String: Any]
        let propertiesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(properties)) as? [String: Any]

        let schedule = digestJSON?["digest_schedule"] as? [String: Any]
        #expect(schedule?["id"] as? String == "weekly")
        #expect(schedule?["time"] as? String == "09:00")
        #expect(schedule?["weekdays"] as? [String] == ["mo"])
        #expect(schedule?["dtstart"] == nil)
        #expect(digestJSON?["preference"] as? String == "opt_in")

        let items = propertiesJSON?["properties"] as? [[String: Any]]
        #expect(items?.first?["key"] as? String == "count")
        #expect(items?.first?["value"] as? Double == 3)
        #expect(items?.last?["value"] as? [String] == ["a"])
        #expect(propertiesJSON?["preference"] as? String == "opt_out")
    }

    private func decodeCategory(_ json: String) throws -> SuprSend.Category {
        try JSONDecoder().decode(SuprSend.Category.self, from: Data(json.utf8))
    }

    private static let richCategoryJSON = """
        {
          "name": "Marketing",
          "category": "marketing",
          "preference": "opt_in",
          "is_editable": true,
          "channels": [],
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

    private func seededClient() async throws -> SuprSendClient {
        let client = SuprSendClient(publicKey: "test-key")
        _ = await client.user.preferences.getPreferences(args: .init(tenantId: "tenant-a"))
        client.user.preferences.data = try JSONDecoder().decode(PreferenceData.self, from: Self.seedJSON)
        return client
    }

    private static let seedJSON = Data(
        """
        {
          "sections": [
            {
              "name": "s",
              "subcategories": [
                {
                  "name": "Marketing",
                  "category": "marketing",
                  "preference": "opt_in",
                  "is_editable": true,
                  "channels": []
                }
              ]
            }
          ],
          "channel_preferences": []
        }
        """.utf8)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
