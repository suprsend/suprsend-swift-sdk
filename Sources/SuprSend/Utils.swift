//
//  Utils.swift
//  SuprSend
//
//  Created by Ram Suthar on 22/08/24.
//

import Foundation
import OSLog

/// A utility class providing various helper methods.
final class Utils: Sendable {
    /// Shared instance of the `Utils` class.
    static let shared = Utils()

    /// Retrieves a string value from the local storage using the specified key.
    ///
    /// - Parameter key: The key to retrieve the value for.
    /// - Returns: The retrieved string value, or nil if not found.
    func getLocalStorageData(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    /// Sets a string value in the local storage using the specified key.
    ///
    /// - Parameter key: The key to store the value under.
    /// - Parameter value: The string value to store.
    func setLocalStorageData(key: String, value: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }

    /// Removes a stored value from the local storage using the specified key.
    ///
    /// - Parameter key: The key to remove the value for.
    func removeLocalStorageData(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
    }

    /// Decodes a JWT token into a dictionary of string-to-any values.
    ///
    /// - Parameter jwt: The JWT token to decode.
    /// - Returns: A dictionary containing the decoded payload, or throws an error if decoding fails.
    func decode(jwtToken jwt: String) throws -> [String: Any] {

        enum DecodeErrors: Error {
            case badToken
            case other
        }

        /// Decodes a base64-encoded string into Data.
        ///
        /// - Parameter base64: The base64-encoded string to decode.
        /// - Returns: The decoded Data, or throws an error if decoding fails.
        func base64Decode(_ base64: String) throws -> Data {
            let base64 =
                base64
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let padded = base64.padding(
                toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let decoded = Data(base64Encoded: padded) else {
                throw DecodeErrors.badToken
            }
            return decoded
        }

        /// Decodes a JWT part into a dictionary of string-to-any values.
        ///
        /// - Parameter value: The JWT part to decode.
        /// - Returns: A dictionary containing the decoded payload, or throws an error if decoding fails.
        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            let bodyData = try base64Decode(value)
            let json = try JSONSerialization.jsonObject(with: bodyData, options: [])
            guard let payload = json as? [String: Any] else {
                throw DecodeErrors.other
            }
            return payload
        }

        let segments = jwt.components(separatedBy: ".")
        guard segments.count > 2 else {
            throw DecodeErrors.badToken
        }
        return try decodeJWTPart(segments[1])
    }

    /// Validates an `EventProperty` dictionary, removing reserved keys if allowed.
    ///
    /// - Parameter data: The `EventProperty` dictionary to validate.
    /// - Parameter options: Optional validation options (default is nil).
    /// - Returns: A validated `EventProperty` dictionary with reserved keys removed if allowed.
    func validateObjData(data: EventProperty, options: ValidatedDataOptions? = nil) -> EventProperty
    {
        var validatedData = EventProperty()
        let allowReservedKeys = options?.allowReservedKeys ?? false
        let valueType = options?.valueType

        for (key, value) in data {
            if !allowReservedKeys && isReservedKey(key) {
                logger.warning("Reserved key \(key) is not allowed")
                logger.warning("[SuprSend]: key cannot start with $ or ss_")
                continue
            }

            validatedData[key] = value
        }
        return validatedData
    }

    /// Validates an array of strings, removing reserved keys if allowed.
    ///
    /// - Parameter data: The array of strings to validate.
    /// - Returns: A validated array of strings with reserved keys removed if allowed.
    func validateArrayData(data: [String]) -> [String] {
        var validatedData: [String] = []

        for item in data {
            if isReservedKey(item) {
                logger.warning("Reserved key \(item) is not allowed")
                logger.warning("[SuprSend]: key cannot start with $ or ss_")
                continue
            }
            validatedData.append(item)
        }
        return validatedData
    }

    /// Checks whether a given string key is reserved.
    ///
    /// - Parameter key: The string key to check.
    /// - Returns: True if the key is reserved, false otherwise.
    func isReservedKey(_ key: String) -> Bool {
        key.hasPrefix("$") || key.lowercased().hasPrefix("ss_")
    }

    /// Validates an email address against a regular expression pattern.
    ///
    /// - Parameter email: The email address to validate.
    /// - Returns: True if the email is valid, false otherwise.
    func validateEmail(email: String) -> Bool {
        return email.range(of: Constants.emailRegex, options: .regularExpression) != nil
    }

    /// Validates a phone number against a regular expression pattern.
    ///
    /// - Parameter phone: The phone number to validate.
    /// - Returns: True if the phone number is valid, false otherwise.
    func validatePhone(phone: String) -> Bool {
        return phone.range(of: Constants.phoneRegex, options: .regularExpression) != nil
    }
}
