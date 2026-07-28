import Foundation

/// Configuration for this example app — edit these to point it at your own workspace.
enum SuprSendConstants {
    static let publicKey: String = ""
    static let host: String? = nil  // optional override for self-hosted collectors

    /// Backend that mints JWT user tokens. Point this at your own to exercise the
    /// authenticated identify flow; while it's blank the example falls back to an
    /// unauthenticated `identify(distinctID:)`.
    static let tokenBaseURL: String = ""

    /// Inbox feed hosts. These are *separate* from `host` above — the inbox does
    /// not route through the collector, so pointing `host` at a staging collector
    /// leaves the feed on its own endpoints. Leave both `nil` to use the SDK's
    /// defaults; set either to override just that one.
    static let feedAPIHost: String? = nil
    static let feedSocketHost: String? = nil
}

/// UserDefaults keys backing the example's login state. Internal plumbing, not SDK
/// configuration — named because each key is read both via @AppStorage in the views
/// and directly from UserDefaults in AppDelegate.
enum StorageKeys {
    static let distinctID: String = "suprsend_example_distinct_id"
    static let tenantID: String = "suprsend_example_tenant_id"
    static let enableUserToken: String = "suprsend_example_enable_user_token"
}
