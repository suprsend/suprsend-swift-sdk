//
//  APIClient.swift
//  SuprSend
//
//  Created by Ram Suthar on 21/08/24.
//

import Foundation

class APIClient {
    private let config: SuprSendClient

    /// Coalesces concurrent token refreshes: API calls that all find the token
    /// expiring at the same moment share a single `refreshUserToken` callback
    /// and a single re-identify instead of triggering one each.
    private let tokenRefresher = SharedInflightTask()

    /// Initializes the API client with a configuration.
    /// - Parameter config: The configuration to use for the API client.
    init(config: SuprSendClient) {
        self.config = config
    }

    /// Gets the full URL with the given path.
    /// - Parameter path: The path to append to the base URL.
    /// - Returns: The full URL, or nil if the base URL is invalid.
    private func getUrl(path: String) -> URL? {
        if path.hasPrefix("https://") || path.hasPrefix("http://") {
            URL(string: path)
        } else if config.host.hasSuffix("/") {
            URL(string: config.host + path)
        } else {
            URL(string: config.host + "/" + path)
        }
    }

    /// Gets the headers for API requests.
    /// - Returns: A dictionary of headers to include in API requests.
    private func getHeaders() -> [String: String] {
        var headers = [
            Constants.headerContentType: Constants.headerApplicationJSON,
            Constants.headerAuthorization: config.publicKey,
            Constants.headerXClientUserAgent: config.clientUserAgentJSON,
            Constants.headerXUserAgent: config.userAgent,
        ]

        if let token = config.userToken {
            headers[Constants.headerXSignature] = token
        }

        return headers
    }

    /// Makes an API request using the given data.
    /// - Parameter reqData: The data to use for the API request.
    /// - Returns: A response object representing the result of the API request.
    private func requestApiInstance<R: Response>(reqData: HandleRequest) async throws -> R {
        switch reqData.type {
        case .get:
            try await get(path: reqData.path)
        case .post:
            try await post(path: reqData.path, payload: reqData.payload ?? .empty)
        case .patch:
            try await patch(path: reqData.path, payload: reqData.payload ?? .empty)
        }
    }

    /// Makes a GET API request using the given path.
    /// - Parameter path: The path to use for the GET request.
    /// - Returns: A response object representing the result of the GET request.
    private func get<R: Response>(path: String) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .get, headers: getHeaders())
    }

    /// Makes a POST API request using the given path and payload.
    /// - Parameter path: The path to use for the POST request.
    /// - Parameter payload: The data to include in the POST request body.
    /// - Returns: A response object representing the result of the POST request.
    private func post<R: Response>(path: String, payload: AnyEncodable) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .post, body: payload, headers: getHeaders())
    }

    /// Makes a PATCH API request using the given path and payload.
    /// - Parameter path: The path to use for the PATCH request.
    /// - Parameter payload: The data to include in the PATCH request body.
    /// - Returns: A response object representing the result of the PATCH request.
    private func patch<R: Response>(path: String, payload: AnyEncodable) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .patch, body: payload, headers: getHeaders())
    }

    /// Whether a token expiring at `expiresOn` (JWT `exp`, seconds since epoch)
    /// should be refreshed at `now`: it has already expired, or will within
    /// `Constants.userTokenRefreshBefore`.
    static func isUserTokenExpiring(expiresOn: TimeInterval, now: TimeInterval) -> Bool {
        expiresOn - Constants.userTokenRefreshBefore <= now
    }

    /// Refreshes `userToken` on demand via the app-supplied `refreshUserToken`
    /// callback when it has expired or is about to (see ``isUserTokenExpiring``).
    ///
    /// Called before every authenticated request, and by `Feed` on socket
    /// connection loss, so a refresh is never missed because the app was
    /// suspended or backgrounded (unlike a scheduled timer). No-op when there's
    /// no token or callback, when the token can't be decoded or has no `exp`,
    /// or when it's still comfortably valid. Concurrent callers share one
    /// refresh. Failures are logged and swallowed so the pending request still
    /// goes out and surfaces the real auth error, if any.
    func refreshExpiringUserToken() async {
        guard let distinctID = config.distinctID,
              let userToken = config.userToken,
              let refreshUserToken = config.authenticateOptions?.refreshUserToken else {
            return
        }

        guard let jwtPayload = try? Utils.shared.decode(jwtToken: userToken) else {
            logger.warning("[SuprSend]: Couldn't decode userToken, skipping refresh")
            return
        }

        // A token without `exp` never expires, so there's nothing to refresh.
        guard let expiresOn = jwtPayload[Constants.expiryKeyJWT] as? Double else {
            return
        }

        guard Self.isUserTokenExpiring(expiresOn: expiresOn, now: Date.now.timeIntervalSince1970) else {
            return
        }

        await tokenRefresher.run { [config] in
            do {
                // Empty string is treated like `nil`: the callback couldn't
                // produce a token, so keep the current one (matches web SDK).
                guard let newUserToken = try await refreshUserToken(userToken, jwtPayload),
                      !newUserToken.isEmpty else {
                    return
                }

                // The app's callback may take a while; if the session changed
                // underneath it (`reset()`, a different user identified, or the
                // app installed a newer token itself) the result belongs to a
                // session that no longer exists — don't graft it onto the new one.
                guard config.distinctID == distinctID, config.userToken == userToken else {
                    logger.warning("[SuprSend]: Session changed while refreshing userToken, discarding refreshed token")
                    return
                }

                _ = await config.identify(
                    distinctID: distinctID,
                    userToken: newUserToken,
                    options: config.authenticateOptions
                )
            } catch {
                logger.warning("[SuprSend]: Couldn't fetch new userToken: \(error.localizedDescription)")
            }
        }
    }

    /// Makes an API request using the given data.
    /// - Parameter reqData: The data to use for the API request.
    /// - Returns: A response object representing the result of the API request.
    func request<R: Response>(reqData: HandleRequest) async -> R {
        guard config.distinctID != nil else {
            return .error(
                .init(
                    type: .validation,
                    message:
                        "User isn't authenticated. Call identify method before performing any action"
                ))
        }

        await refreshExpiringUserToken()

        do {
            return try await requestApiInstance(reqData: reqData)
        } catch {
            logger.error("SuprSend: \(reqData.type.rawValue) \(reqData.path) error: \(error.localizedDescription)")
            return .error(
                .init(type: .network, message: error.localizedDescription), statusCode: 500)
        }
    }
    
    func publicRequest<R: Response>(reqData: HandleRequest) async -> R {
        do {
            return try await requestApiInstance(reqData: reqData)
        } catch {
            logger.error("SuprSend: \(reqData.type.rawValue) \(reqData.path) error: \(error.localizedDescription)")
            return .error(
                .init(type: .network, message: error.localizedDescription), statusCode: 500)
        }
    }

    /// Fetches data from the given URL using the specified method and headers.
    /// - Parameters:
    ///   - url: The URL to fetch data from.
    ///   - method: The HTTP method to use for the request.
    ///   - body: The data to include in the request body (optional).
    ///   - headers: The headers to include in the request (optional).
    /// - Returns: A response object representing the result of the fetch request.
    private func fetch<R: Response>(
        _ url: URL,
        method: HandleRequest.RequestType,
        body: AnyEncodable? = nil,
        headers: [String: String]?
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = response as? HTTPURLResponse
        let methodString = method.rawValue
        let urlString = url.absoluteString

        do {
            let decoded = try JSONDecoder().decode(R.self, from: data)
            if let httpResponse {
                if data.isEmpty {
                    logger.error("SuprSend: \(methodString) \(urlString) \(httpResponse.statusCode) \(decoded.status.rawValue)")
                } else {
                    logger.info("SuprSend: \(methodString) \(urlString) \(httpResponse.statusCode)")
                }
            }
            if let message = decoded.error?.message {
                logger.error("SuprSend: \(methodString) \(urlString) \(httpResponse?.statusCode ?? 0) \(message)")
            }

            // Server doesn't echo HTTP status into the JSON body — populate
            // statusCode from the actual HTTP response so callers can see it.
            return R.init(
                status: decoded.status,
                statusCode: httpResponse?.statusCode,
                body: decoded.body,
                error: decoded.error
            )
        } catch {
            logger.error("SuprSend: \(methodString) \(urlString) \(httpResponse?.statusCode ?? 0) \(String(data: data, encoding: .utf8) ?? "") error: \(error.localizedDescription)")
        }

        return .error(.init(type: .unknown, message: nil), statusCode: httpResponse?.statusCode)
    }
}

/// Coalesces concurrent invocations of an async operation: callers arriving
/// while a run is in flight await that same run instead of starting another.
actor SharedInflightTask {
    private var inflight: Task<Void, Never>?

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        if inflight == nil {
            // The task inherits this actor's isolation, so `finish()` runs
            // isolated as soon as the operation returns — there's no window in
            // which `inflight` still points at a completed run.
            inflight = Task {
                await operation()
                self.finish()
            }
        }

        await inflight?.value
    }

    private func finish() {
        inflight = nil
    }
}
