//
//  UserAgentTests.swift
//  SuprSendTests
//

import Testing
import Foundation
@testable import SuprSend

struct UserAgentTests {

    @Test func defaultsArePopulatedFromConstantsAndDetection() {
        let ua = buildClientUserAgent()

        #expect(ua.sdk == Constants.sdkName)
        #expect(ua.sdkVersion == Constants.sdkVersion)
        #expect(ua.lang == "swift")
        // langVersion is detected at compile time via `swift(>=X.Y)` rungs;
        // anything from Swift 5.6 upward should populate a non-empty value.
        #expect(!(ua.langVersion?.isEmpty ?? true))

        #if os(iOS)
        #expect(ua.platform == "ios")
        #expect(ua.os == "ios")
        #expect(ua.environment == "mobile" || ua.environment == "tablet")
        #expect(!(ua.osVersion?.isEmpty ?? true))
        #elseif os(macOS)
        #expect(ua.platform == "macos")
        #expect(ua.os == "macos")
        #expect(ua.environment == "desktop")
        #expect(!(ua.osVersion?.isEmpty ?? true))
        #endif

        // device_model: nil on simulators that don't expose hw.machine,
        // non-empty otherwise. Either is acceptable; assert it isn't an empty
        // string when present.
        if let model = ua.deviceModel {
            #expect(!model.isEmpty)
        }
    }

    @Test func appInfoFromCallerIsCarried() {
        let ua = buildClientUserAgent(
            appInfo: AppInfo(name: "Acme", version: "1.2.3")
        )

        #expect(ua.appInfo?.name == "Acme")
        #expect(ua.appInfo?.version == "1.2.3")
    }

    @Test func appInfoNameOnlyIsAttached() {
        let ua = buildClientUserAgent(
            appInfo: AppInfo(name: "OnlyName")
        )

        #expect(ua.appInfo?.name == "OnlyName")
        #expect(ua.appInfo?.version == nil)
    }

    @Test func appInfoWithoutNameIsDropped() {
        // Only a version, no name — entire app_info block should be omitted.
        let ua = buildClientUserAgent(
            appInfo: AppInfo(version: "1.2.3")
        )
        #expect(ua.appInfo == nil)

        // Empty-string name should also be treated as "no name".
        let ua2 = buildClientUserAgent(
            appInfo: AppInfo(name: "", version: "1.2.3")
        )
        #expect(ua2.appInfo == nil)

        // Same rule applies when the missing name comes from the override
        // shadowing the underlying appInfo's name with nothing.
        let ua3 = buildClientUserAgent(
            override: ClientUserAgentConfig(appInfo: AppInfo(version: "9.9"))
        )
        #expect(ua3.appInfo == nil)

        // And confirm it stays out of the JSON payload.
        let json = encodeClientUserAgent(ua)
        #expect(!json.contains("\"app_info\""))
    }

    @Test func overrideWinsPerField() {
        let ua = buildClientUserAgent(
            override: ClientUserAgentConfig(platform: "custom-platform")
        )

        #expect(ua.platform == "custom-platform")
        // Unrelated defaults still populated
        #expect(ua.sdk == Constants.sdkName)
        #expect(ua.lang == "swift")
    }

    @Test func overrideAppInfoMergesNestedFields() {
        let ua = buildClientUserAgent(
            appInfo: AppInfo(name: "BaseApp", version: "1.0.0"),
            override: ClientUserAgentConfig(
                appInfo: AppInfo(version: "9.9.9")
            )
        )

        #expect(ua.appInfo?.name == "BaseApp")     // preserved
        #expect(ua.appInfo?.version == "9.9.9")     // overridden
    }

    @Test func userAgentStringIncludesSdkAndOs() {
        let ua = buildClientUserAgent()
        let s = buildUserAgent(ua)

        #expect(s.hasPrefix("\(Constants.sdkName)/\(Constants.sdkVersion)"))
        #expect(s.contains("swift"))

        #if os(iOS)
        #expect(s.contains("ios"))
        #elseif os(macOS)
        #expect(s.contains("macos"))
        #endif
    }

    @Test func userAgentStringIncludesAppPartWhenPresent() {
        let ua = buildClientUserAgent(
            appInfo: AppInfo(name: "Acme", version: "1.2.3")
        )
        let s = buildUserAgent(ua)

        #expect(s.contains("(Acme/1.2.3)"))
    }

    @Test func userAgentStringOmitsAppPartWhenAbsent() {
        let ua = ClientUserAgentConfig(
            sdk: "test-sdk",
            sdkVersion: "0.1.0",
            lang: "swift",
            os: "ios"
        )
        let s = buildUserAgent(ua)

        #expect(s == "test-sdk/0.1.0 (swift; ios)")
    }

    @Test func userAgentStringIncludesLangVersionWhenPresent() {
        let ua = ClientUserAgentConfig(
            sdk: "test-sdk",
            sdkVersion: "0.1.0",
            lang: "swift",
            langVersion: "5.10",
            os: "ios"
        )
        let s = buildUserAgent(ua)

        #expect(s == "test-sdk/0.1.0 (swift/5.10; ios)")
    }

    @Test func langVersionIsEncodedAsSnakeCaseInJSON() throws {
        let ua = ClientUserAgentConfig(
            sdk: "test-sdk",
            sdkVersion: "0.1.0",
            lang: "swift",
            langVersion: "5.10"
        )
        let json = encodeClientUserAgent(ua)

        #expect(json.contains("\"lang_version\":\"5.10\""))
        // langVersion (camelCase) must not leak to the wire
        #expect(!json.contains("\"langVersion\""))
    }

    @Test func langVersionOverrideWins() {
        let ua = buildClientUserAgent(
            override: ClientUserAgentConfig(langVersion: "9.9")
        )

        #expect(ua.langVersion == "9.9")
    }

    @Test func jsonEncodingUsesSnakeCaseAndSkipsNil() throws {
        let ua = ClientUserAgentConfig(
            sdk: "test-sdk",
            sdkVersion: "0.1.0",
            lang: "swift",
            platform: "ios",
            os: "ios",
            osVersion: "17.0",
            appInfo: AppInfo(name: "Acme", version: "1.0"),
            deviceModel: "iPhone14,3"
        )
        let json = encodeClientUserAgent(ua)

        #expect(json.contains("\"sdk_version\":\"0.1.0\""))
        #expect(json.contains("\"os_version\":\"17.0\""))
        #expect(json.contains("\"app_info\""))
        #expect(json.contains("\"device_model\":\"iPhone14,3\""))
        // environment was nil — must not appear in payload
        #expect(!json.contains("\"environment\""))
        #expect(!json.contains("null"))

        // Round-trip parse to confirm it's valid JSON
        let data = try #require(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["sdk"] as? String == "test-sdk")
        let app = parsed?["app_info"] as? [String: Any]
        #expect(app?["name"] as? String == "Acme")
    }

    @Test func clientReadsUserAgentFromOptions() {
        let client = SuprSendClient(
            publicKey: "test-key",
            options: Options(
                appInfo: AppInfo(name: "FromOptions", version: "0.0.1")
            )
        )

        #expect(client.userAgent.contains("FromOptions/0.0.1"))
        #expect(client.clientUserAgentJSON.contains("\"name\":\"FromOptions\""))
        #expect(client.clientUserAgentJSON.contains("\"version\":\"0.0.1\""))
    }
}
