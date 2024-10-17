//
//  APIClient.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 21/08/24.
//

import Foundation

class APIClient {
    private let config: SuprSend

    /// Initializes the API client with a configuration.
    ///
    /// - Parameter config: The configuration to use for the API client.
    init(config: SuprSend) {
        self.config = config
    }

    /// Gets the full URL with the given path.
    ///
    /// - Parameter path: The path to append to the base URL.
    /// - Returns: The full URL, or nil if the base URL is invalid.
    private func getUrl(path: String) -> URL? {
        return URL(string: config.host)?.appendingPathComponent(path)
    }

    /// Gets the headers for API requests.
    ///
    /// - Returns: A dictionary of headers to include in API requests.
    private func getHeaders() -> [String: String] {
        var headers = [
            Constants.headerContentType: Constants.headerApplicationJSON,
            Constants.headerAuthorization: config.publicKey,
        ]

        if let token = config.userToken {
            headers[Constants.headerXSignature] = token
        }

        return headers
    }

    /// Makes an API request using the given data.
    ///
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
    ///
    /// - Parameter path: The path to use for the GET request.
    /// - Returns: A response object representing the result of the GET request.
    private func get<R: Response>(path: String) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .get, headers: getHeaders())
    }

    /// Makes a POST API request using the given path and payload.
    ///
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
    ///
    /// - Parameter path: The path to use for the PATCH request.
    /// - Parameter payload: The data to include in the PATCH request body.
    /// - Returns: A response object representing the result of the PATCH request.
    private func patch<R: Response>(path: String, payload: AnyEncodable) async throws -> R {
        guard let url = getUrl(path: path) else {
            return .error(.init(type: .validation, message: "Can't create a URL for path: \(path)"))
        }

        return try await fetch(url, method: .patch, body: payload, headers: getHeaders())
    }

    /// Makes an API request using the given data.
    ///
    /// - Parameter reqData: The data to use for the API request.
    /// - Returns: A response object representing the result of the API request.
    func request<R: Response>(reqData: HandleRequest) async -> R {
        guard let distinctID = config.distinctID else {
            return .error(
                .init(
                    type: .validation,
                    message:
                        "User isn't authenticated. Call identify method before performing any action"
                ))
        }

        if let refreshUserToken = config.authenticateOptions?.refreshUserToken,
            let userToken = config.userToken
        {

            let jwtPayload = try? Utils.shared.decode(jwtToken: userToken)
            let expiresOn = (jwtPayload?[Constants.expiryKeyJWT] as? Double ?? .zero)
            let now = Date.now.timeIntervalSince1970
            let hasExpired = expiresOn <= now

            if hasExpired {
                do {
                    let newUserToken = try await refreshUserToken(
                        userToken,
                        jwtPayload ?? .init()
                    )

                    if let newUserToken {
                        _ = await config.identify(
                            distinctID: distinctID,
                            userToken: newUserToken,
                            options: config.authenticateOptions
                        )
                    }
                } catch {
                    // error while getting token go ahead with calling api
                }
            }

            do {
                return try await requestApiInstance(reqData: reqData)
            } catch {
                logger.error("Error while calling API: \(error)")
                return .error(
                    .init(type: .network, message: error.localizedDescription), statusCode: 500)
            }
        }

        return .error(.init(type: .validation, message: "User token is missing"))
    }
    
    func publicRequest<R: Response>(reqData: HandleRequest) async -> R {
        do {
            return try await requestApiInstance(reqData: reqData)
        } catch {
            logger.error("Error while calling API: \(error)")
            return .error(
                .init(type: .network, message: error.localizedDescription), statusCode: 500)
        }
    }

    /// Fetches data from the given URL using the specified method and headers.
    ///
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

        //        let json = try JSONSerialization.jsonObject(with: data, options: [])
        //        return .success(statusCode: httpResponse?.statusCode, body: json as? R.Body)

        let result = try JSONDecoder().decode(R.self, from: data)
        if let httpResponse = response as? HTTPURLResponse {
            if data.isEmpty {
                logger.error("SuprSend: \(httpResponse.statusCode) \(result.status.rawValue)")
            } else {
                logger.info(
                    "SuprSend: \(httpResponse.statusCode) \(String(data: data, encoding: .utf8)!)")
            }
        }
        if let message = result.error?.message {
            logger.error("\(message)")
        }

        return result
    }
}
