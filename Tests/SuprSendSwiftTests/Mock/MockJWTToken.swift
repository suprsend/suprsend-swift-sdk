//
//  MockJWTToken.swift
//  SuprSendSwiftTests
//
//  Created by Ram Suthar on 16/09/24.
//

import Foundation
import CryptoKit

class MockJWTToken {

    let secret = """
-----BEGIN PRIVATE KEY-----
<YOUR PRIVATE KEY>
-----END PRIVATE KEY-----
"""
    
    struct Header: Encodable {
        let alg = "ES256"
        let typ = "JWT"
    }

    struct Payload: Encodable {
        let entity_type: String = "subscriber" // hardcode this value to subscriber
        let entity_id: String
        let exp: UInt = UInt(Date.now.timeIntervalSince1970) + 3600 // token expiry timestamp in seconds
        let iat: UInt = UInt(Date.now.timeIntervalSince1970)
    }
    
    func generate(for distinctId: String) throws -> String {

        let headerJSONData = try JSONEncoder().encode(Header())
        let headerBase64String = headerJSONData.urlSafeBase64EncodedString()

        let payloadJSONData = try JSONEncoder().encode(Payload(entity_id: distinctId))
        let payloadBase64String = payloadJSONData.urlSafeBase64EncodedString()

        let toSign = Data((headerBase64String + "." + payloadBase64String).utf8)

        let key = try P256.Signing.PrivateKey(pemRepresentation: secret)
        let signature = try key.signature(for: toSign)
        let signatureBase64String = signature.rawRepresentation.urlSafeBase64EncodedString()

        let token = [headerBase64String, payloadBase64String, signatureBase64String].joined(separator: ".")
        return token
    }
}

extension Data {
    func urlSafeBase64EncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
