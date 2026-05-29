import Foundation
import SuprSend

/// Fetches JWT user tokens used to authenticate users with SuprSend, and wires
/// up automatic refresh so the SDK can renew the token before it expires.
enum SuprSendTokenService {
    /// Backend endpoint that mints a JWT for a given distinct id.
    /// Point this at your own JWT-minting service. When the endpoint is
    /// unreachable, `identify(distinctID:)` falls back to an unauthenticated
    /// call so the example stays usable for quick experiments.
    private static let tokenBaseURL = "http://127.0.0.1:8000/authentication-token"

    private struct TokenResponse: Decodable {
        let token: String
    }

    /// Requests a fresh JWT user token for the given distinct id.
    ///
    /// Mirrors the backend `getToken(user, tenant)` helper.
    static func fetchToken(for distinctID: String, tenantID: String? = nil) async throws -> String {
        let encodedID = distinctID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? distinctID
        var components = URLComponents(string: "\(tokenBaseURL)/\(encodedID)")
        if let tenantID {
            components?.queryItems = [URLQueryItem(name: "tenant_id", value: tenantID)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }

    /// Identifies the user with SuprSend using a freshly minted JWT and registers
    /// a refresh callback the SDK invokes before the token expires.
    ///
    /// If the token can't be fetched, falls back to an unauthenticated identify
    /// so the example app stays usable.
    @discardableResult
    static func identify(distinctID: String, tenantID: String? = nil) async -> APIResponse {
        let options = AuthenticateOptions(refreshUserToken: { _, _ in
            // The SDK calls this when the token is close to expiry; re-mint it.
            try await fetchToken(for: distinctID, tenantID: tenantID)
        })

        do {
            let token = try await fetchToken(for: distinctID, tenantID: tenantID)
            return await SuprSend.shared.identify(distinctID: distinctID, userToken: token, options: options)
        } catch {
            print("[SwiftExample] Failed to fetch SuprSend user token: \(error)")
            return await SuprSend.shared.identify(distinctID: distinctID)
        }
    }
}
