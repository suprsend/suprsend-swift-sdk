//
//  AuthenticateOptions.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 24/08/24.
//

import Foundation

public typealias RefreshTokenCallback = (_ oldUserToken: String, _ tokenPayload: [String: Any])
    async throws -> String?

public struct AuthenticateOptions {
    /// The callback to refresh the user token.
    let refreshUserToken: RefreshTokenCallback
}
