//
//  AuthenticateOptions.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 24/08/24.
//

import Foundation

public typealias RefreshTokenCallback = (_ oldUserToken: String, _ tokenPayload: [String: Any])
    async throws -> String?

public class AuthenticateOptions {
    /// The callback to refresh the user token.
    let refreshUserToken: RefreshTokenCallback
    
    public init(refreshUserToken: @escaping RefreshTokenCallback) {
        self.refreshUserToken = refreshUserToken
    }
}
