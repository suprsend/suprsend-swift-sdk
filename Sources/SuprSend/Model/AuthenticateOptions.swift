import Foundation

public typealias RefreshTokenCallback = (_ oldUserToken: String, _ tokenPayload: [String: Any])
    async throws -> String?

public class AuthenticateOptions {
    let refreshUserToken: RefreshTokenCallback
    
    public init(refreshUserToken: @escaping RefreshTokenCallback) {
        self.refreshUserToken = refreshUserToken
    }
}
