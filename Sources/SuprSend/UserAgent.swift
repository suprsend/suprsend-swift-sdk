//
//  UserAgent.swift
//  SuprSend
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// App-level info merged into the user-agent payload.
///
/// Mirrors the `AppInfo` interface from the web SDK. Supplied by the caller
/// via ``Options/appInfo``; when not supplied, the `app_info` block is
/// omitted from the user-agent payload entirely.
public struct AppInfo: Sendable {
    public let name: String?
    public let version: String?

    public init(name: String? = nil, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

/// SDK + runtime + OS + app payload sent on the
/// `X-Suprsend-Client-User-Agent` header (JSON-encoded). Mirrors the web SDK's
/// `ClientUserAgentConfig` field-for-field; `browser` / `browser_version` are
/// omitted because they don't apply to native Apple platforms.
public struct ClientUserAgentConfig: Sendable {
    public let sdk: String?
    public let sdkVersion: String?
    public let lang: String?
    public let langVersion: String?
    public let platform: String?
    public let environment: String?
    public let os: String?
    public let osVersion: String?
    public let appInfo: AppInfo?
    public let deviceModel: String?

    public init(
        sdk: String? = nil,
        sdkVersion: String? = nil,
        lang: String? = nil,
        langVersion: String? = nil,
        platform: String? = nil,
        environment: String? = nil,
        os: String? = nil,
        osVersion: String? = nil,
        appInfo: AppInfo? = nil,
        deviceModel: String? = nil
    ) {
        self.sdk = sdk
        self.sdkVersion = sdkVersion
        self.lang = lang
        self.langVersion = langVersion
        self.platform = platform
        self.environment = environment
        self.os = os
        self.osVersion = osVersion
        self.appInfo = appInfo
        self.deviceModel = deviceModel
    }
}

extension AppInfo: Encodable {
    enum CodingKeys: String, CodingKey {
        case name
        case version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(version, forKey: .version)
    }
}

extension ClientUserAgentConfig: Encodable {
    enum CodingKeys: String, CodingKey {
        case sdk
        case sdkVersion = "sdk_version"
        case lang
        case langVersion = "lang_version"
        case platform
        case environment
        case os
        case osVersion = "os_version"
        case appInfo = "app_info"
        case deviceModel = "device_model"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sdk, forKey: .sdk)
        try c.encodeIfPresent(sdkVersion, forKey: .sdkVersion)
        try c.encodeIfPresent(lang, forKey: .lang)
        try c.encodeIfPresent(langVersion, forKey: .langVersion)
        try c.encodeIfPresent(platform, forKey: .platform)
        try c.encodeIfPresent(environment, forKey: .environment)
        try c.encodeIfPresent(os, forKey: .os)
        try c.encodeIfPresent(osVersion, forKey: .osVersion)
        try c.encodeIfPresent(appInfo, forKey: .appInfo)
        try c.encodeIfPresent(deviceModel, forKey: .deviceModel)
    }
}

enum UserAgentDetection {
    static func detectOS() -> (os: String, osVersion: String) {
        #if os(iOS)
        return ("ios", UIDevice.current.systemVersion)
        #elseif os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return ("macos", "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        #else
        return ("unknown", "")
        #endif
    }

    static func detectEnvironment() -> String {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "tablet"
        case .phone, .carPlay, .unspecified: return "mobile"
        default: return "desktop"
        }
        #else
        return "desktop"
        #endif
    }

    /// Raw hardware identifier (e.g. `iPhone14,3`, `Mac15,7`). Server-side can
    /// map to display names.
    static func detectDeviceModel() -> String {
        var sysinfo = utsname()
        guard uname(&sysinfo) == 0 else { return "" }
        return withUnsafeBytes(of: &sysinfo.machine) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return ""
            }
            return String(cString: base)
        }
    }

    /// Swift language version the SDK was compiled against. Picks the highest
    /// matching `swift(>=X.Y)` rung — equivalent to what `python --version`
    /// reports for the web SDK's `lang_version`.
    static func detectLangVersion() -> String {
        #if swift(>=6.1)
        return "6.1"
        #elseif swift(>=6.0)
        return "6.0"
        #elseif swift(>=5.10)
        return "5.10"
        #elseif swift(>=5.9)
        return "5.9"
        #elseif swift(>=5.8)
        return "5.8"
        #elseif swift(>=5.7)
        return "5.7"
        #elseif swift(>=5.6)
        return "5.6"
        #else
        return ""
        #endif
    }

}

/// Builds the effective ``ClientUserAgentConfig`` by layering caller-supplied
/// values over detected defaults.
///
/// Precedence (matches web SDK `buildClientUserAgent`):
/// 1. `override` fields (per-field) win when non-nil.
/// 2. Otherwise, `appInfo` is used for the app block.
/// 3. Otherwise, values are auto-detected (OS, version, device, lang version).
///
/// The `app_info` block is purely caller-supplied and gated on `name`: when
/// the resolved `name` is missing or empty, the entire block is omitted from
/// the payload — a stray `version` without a `name` is dropped. When both are
/// present, `override.appInfo` is merged into `appInfo` field-by-field so a
/// caller setting only `appInfo.version` doesn't blank out `appInfo.name`.
func buildClientUserAgent(
    appInfo: AppInfo? = nil,
    override: ClientUserAgentConfig? = nil
) -> ClientUserAgentConfig {
    let (detectedOS, detectedOSVersion) = UserAgentDetection.detectOS()
    let detectedEnv = UserAgentDetection.detectEnvironment()
    let detectedDevice = UserAgentDetection.detectDeviceModel()
    let detectedLangVersion = UserAgentDetection.detectLangVersion()

    // `app_info` is gated on `name`: matches the web SDK's
    // `if (appInfo?.name) { ... }` rule — a caller that supplies only a
    // version (with no name) is treated the same as supplying nothing.
    let resolvedAppName = override?.appInfo?.name ?? appInfo?.name
    let resolvedAppVersion = override?.appInfo?.version ?? appInfo?.version
    let resolvedAppInfo: AppInfo? = (resolvedAppName?.isEmpty == false)
        ? AppInfo(name: resolvedAppName, version: resolvedAppVersion)
        : nil

    return ClientUserAgentConfig(
        sdk: override?.sdk ?? Constants.sdkName,
        sdkVersion: override?.sdkVersion ?? Constants.sdkVersion,
        lang: override?.lang ?? "swift",
        langVersion: override?.langVersion ?? (detectedLangVersion.isEmpty ? nil : detectedLangVersion),
        platform: override?.platform ?? detectedOS,
        environment: override?.environment ?? detectedEnv,
        os: override?.os ?? detectedOS,
        osVersion: override?.osVersion ?? detectedOSVersion,
        appInfo: resolvedAppInfo,
        deviceModel: override?.deviceModel ?? (detectedDevice.isEmpty ? nil : detectedDevice)
    )
}

/// Compact one-line user-agent string for the `X-Suprsend-User-Agent` header.
///
/// Shape: `sdk/version (lang/langVersion; os) (appName/appVersion)`. The
/// `lang/langVersion` segment drops the `/langVersion` suffix when no version
/// is detected. Each parenthesised group is omitted when its contents are
/// empty.
func buildUserAgent(_ config: ClientUserAgentConfig) -> String {
    let sdk = config.sdk ?? ""
    let version = config.sdkVersion ?? ""
    var result = version.isEmpty ? sdk : "\(sdk)/\(version)"

    var detailParts: [String] = []
    if let lang = config.lang, !lang.isEmpty {
        if let lv = config.langVersion, !lv.isEmpty {
            detailParts.append("\(lang)/\(lv)")
        } else {
            detailParts.append(lang)
        }
    }
    if let os = config.os, !os.isEmpty { detailParts.append(os) }
    if !detailParts.isEmpty {
        result += " (\(detailParts.joined(separator: "; ")))"
    }

    if let app = config.appInfo, let name = app.name, !name.isEmpty {
        let appPart: String
        if let v = app.version, !v.isEmpty {
            appPart = "\(name)/\(v)"
        } else {
            appPart = name
        }
        result += " (\(appPart))"
    }

    return result
}

/// JSON-encodes a ``ClientUserAgentConfig`` for the
/// `X-Suprsend-Client-User-Agent` header. Returns `"{}"` on encode failure so
/// the header value is always a valid JSON object.
func encodeClientUserAgent(_ config: ClientUserAgentConfig) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard
        let data = try? encoder.encode(config),
        let json = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return json
}
