//
//  Constants.swift
//  SuprSend
//
//  Created by Ram Suthar on 21/08/24.
//

import Foundation

/// Constants for the iOS SDK.
///
/// This enum provides a collection of constants used throughout the iOS SDK.
enum Constants {
    /// The default host URL for the Suprsend hub.
    static let defaultHost = "https://hub.suprsend.com"

    /// The key for the authenticated distinct ID.
    static let authenticatedDistinctID = "ss_distinct_id"

    /// The key for the device ID.
    static let deviceIDKey = "ss_device_id"

    /// The header key for the x-ss-signature.
    static let headerXSignature = "x-ss-signature"

    /// The header key for authorization.
    static let headerAuthorization = "Authorization"

    /// The header key for content type.
    static let headerContentType = "Content-Type"

    /// The header key for application/json.
    static let headerApplicationJSON = "application/json"

    /// The expiry key for JWT tokens.
    static let expiryKeyJWT = "exp"

    /// The push vendor for APNs.
    static let pushVendor = "apns"

    /// A regular expression pattern for email addresses.
    static let emailRegex = "\\S+@\\S+\\.\\S+"

    /// A regular expression pattern for phone numbers.
    static let phoneRegex = "^\\+[1-9]\\d{1,14}$"

    /// The debounce time in milliseconds.
    static let debounceTime = 1000
}
