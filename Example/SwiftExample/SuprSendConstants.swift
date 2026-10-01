import Foundation

enum SuprSendConstants {
    static let publicKey: String = secret("publicKey") ?? ""
    static let host: String? = secret("host")

    static let tokenBaseURL: String = secret("tokenBaseURL") ?? ""

    static let feedAPIHost: String? = secret("feedAPIHost")
    static let feedSocketHost: String? = secret("feedSocketHost")

    // Secrets.plist is gitignored; copy Secrets.example.plist to create it.
    private static let secrets: [String: Any] =
        Bundle.main.url(forResource: "Secrets", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]

    private static func secret(_ key: String) -> String? {
        guard let value = secrets[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}

enum StorageKeys {
    static let distinctID: String = "suprsend_example_distinct_id"
    static let tenantID: String = "suprsend_example_tenant_id"
    static let enableUserToken: String = "suprsend_example_enable_user_token"
}
