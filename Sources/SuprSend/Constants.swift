import Foundation

enum Constants {
    static let defaultHost = "https://hub.suprsend.com"

    static let authenticatedDistinctID = "ss_distinct_id"

    static let deviceIDKey = "ss_device_id"

    static let headerXSignature = "x-ss-signature"

    static let headerAuthorization = "Authorization"

    static let headerContentType = "Content-Type"

    static let headerApplicationJSON = "application/json"

    static let headerXClientUserAgent = "X-Suprsend-Client-User-Agent"

    static let headerXUserAgent = "X-Suprsend-User-Agent"

    static let sdkName = "suprsend-swift-sdk"

    static let sdkVersion = "2.1.0"

    static let expiryKeyJWT = "exp"

    static let userTokenRefreshBefore: TimeInterval = 30

    static let pushVendor = "apns"

    static let emailRegex = "\\S+@\\S+\\.\\S+"

    static let phoneRegex = "^\\+[1-9]\\d{1,14}$"

    static let debounceTime = 1000
}
