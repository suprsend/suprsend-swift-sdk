import Foundation

final class Utils: Sendable {
    static let shared = Utils()

    func getLocalStorageData(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func setLocalStorageData(key: String, value: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }

    func removeLocalStorageData(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
    }

    func epochMs(_ date: Date = Date()) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    func decode(jwtToken jwt: String) throws -> [String: Any] {

        enum DecodeErrors: Error {
            case badToken
            case other
        }

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

    func validateObjData(data: EventProperty, options: ValidatedDataOptions? = nil) -> EventProperty
    {
        var validatedData = EventProperty()
        let allowReservedKeys = options?.allowReservedKeys ?? false

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

    func isReservedKey(_ key: String) -> Bool {
        key.hasPrefix("$") || key.lowercased().hasPrefix("ss_")
    }

    func validateEmail(email: String) -> Bool {
        return email.range(of: Constants.emailRegex, options: .regularExpression) != nil
    }

    func validatePhone(phone: String) -> Bool {
        return phone.range(of: Constants.phoneRegex, options: .regularExpression) != nil
    }
}
