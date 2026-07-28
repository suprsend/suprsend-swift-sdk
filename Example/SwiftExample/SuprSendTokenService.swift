import Foundation
import SuprSend

/// Fetches JWT user tokens used to authenticate users with SuprSend, and wires
/// up automatic refresh so the SDK can renew the token before it expires.
enum SuprSendTokenService {
    /// Host of the backend that mints JWTs, from `SuprSendConstants.tokenBaseURL`.
    /// When unreachable, the identify fallback runs an unauthenticated call so
    /// the example stays usable for quick experiments.
    private static let tokenBaseURL = SuprSendConstants.tokenBaseURL

    private struct TokenResponse: Decodable {
        let token: String
    }

    /// Requests a fresh JWT user token for the given distinct id.
    ///
    /// Mirrors the backend `getToken(user, tenant)` helper.
    static func fetchToken(for distinctID: String, tenantID: String? = nil) async throws -> String {
        let encodedID = distinctID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? distinctID
        var components = URLComponents(string: "\(tokenBaseURL)/authentication-token/\(encodedID)")
        if let tenantID {
            components?.queryItems = [URLQueryItem(name: "tenant_id", value: tenantID)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }

    /// Identifies the user with SuprSend.
    ///
    /// When `enableUserToken` is true, mints a fresh JWT and registers a refresh
    /// callback the SDK invokes before the token expires. If the token can't be
    /// fetched, falls back to an unauthenticated identify so the example app
    /// stays usable. When false, identifies with just the distinct id (and the
    /// global tenant) — no JWT is fetched and no refresh callback is registered.
    @discardableResult
    static func identify(
        distinctID: String,
        tenantID: String? = nil,
        enableUserToken: Bool
    ) async -> APIResponse {
        // User-token auth disabled: identify with just the distinct id + tenant.
        guard enableUserToken else {
            return await SuprSend.shared.identify(distinctID: distinctID, tenantId: tenantID)
        }

        let options = AuthenticateOptions(refreshUserToken: { _, _ in
            // The SDK calls this when the token is close to expiry; re-mint it.
            try await fetchToken(for: distinctID, tenantID: tenantID)
        })

        do {
            let token = try await fetchToken(for: distinctID, tenantID: tenantID)
            return await SuprSend.shared.identify(
                distinctID: distinctID,
                userToken: token,
                tenantId: tenantID,
                options: options
            )
        } catch {
            print("[SwiftExample] Failed to fetch SuprSend user token: \(error)")
            // Still pass the tenant so it's set as the global tenant even on the
            // unauthenticated fallback (e.g. when the token endpoint is down).
            return await SuprSend.shared.identify(distinctID: distinctID, tenantId: tenantID)
        }
    }
}
