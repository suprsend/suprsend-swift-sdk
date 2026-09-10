import Foundation

class APIClient {
    private let config: SuprSendClient

    private let tokenRefresher = SharedInflightTask()

    init(config: SuprSendClient) {
        self.config = config
    }

    private func getUrl(path: String) -> URL? {
        if path.hasPrefix("https://") || path.hasPrefix("http://") {
            URL(string: path)
        } else if config.host.hasSuffix("/") {
            URL(string: config.host + path)
        } else {
            URL(string: config.host + "/" + path)
        }
    }

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

    private func get<R: Response>(path: String) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .get, headers: getHeaders())
    }

    private func post<R: Response>(path: String, payload: AnyEncodable) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .post, body: payload, headers: getHeaders())
    }

    private func patch<R: Response>(path: String, payload: AnyEncodable) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .patch, body: payload, headers: getHeaders())
    }

    static func isUserTokenExpiring(expiresOn: TimeInterval, now: TimeInterval) -> Bool {
        expiresOn - Constants.userTokenRefreshBefore <= now
    }

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

        guard let expiresOn = jwtPayload[Constants.expiryKeyJWT] as? Double else {
            return
        }

        guard Self.isUserTokenExpiring(expiresOn: expiresOn, now: Date.now.timeIntervalSince1970) else {
            return
        }

        await tokenRefresher.run { [config] in
            do {
                guard let newUserToken = try await refreshUserToken(userToken, jwtPayload),
                      !newUserToken.isEmpty else {
                    return
                }

                // Session changed during the callback; don't apply the token to the new one.
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

            // Server doesn't echo HTTP status in the body; take it from the response.
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

actor SharedInflightTask {
    private var inflight: Task<Void, Never>?

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        if inflight == nil {
            // Task inherits actor isolation, so finish() runs before a stale inflight is observable.
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
