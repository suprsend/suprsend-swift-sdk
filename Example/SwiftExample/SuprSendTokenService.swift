import Foundation
import SuprSend

enum SuprSendTokenService {
    private static let tokenBaseURL = SuprSendConstants.tokenBaseURL

    private struct TokenResponse: Decodable {
        let token: String
    }

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

    @discardableResult
    static func identify(
        distinctID: String,
        tenantID: String? = nil,
        enableUserToken: Bool
    ) async -> APIResponse {
        guard enableUserToken else {
            return await SuprSend.shared.identify(distinctID: distinctID, tenantId: tenantID)
        }

        let options = AuthenticateOptions(refreshUserToken: { _, _ in
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
            return await SuprSend.shared.identify(distinctID: distinctID, tenantId: tenantID)
        }
    }
}
