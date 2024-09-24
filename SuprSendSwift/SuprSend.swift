//
//  SuprSend.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 24/08/24.
//

import Foundation

/// SuprSend iOS Client
public class SuprSend {
    
    public static let shared = SuprSend(publicKey: "")

    /// Additional configurations
    /// - Parameters:
    ///   - host: Host URL
    ///   - vapidKey: VAPID key
    public struct Options {
        /// Host URL
        public let host: String?
        public let enhancedSecurity: Bool
        
        public init(host: String?, enhancedSecurity: Bool) {
            self.host = host
            self.enhancedSecurity = enhancedSecurity
        }
    }

    var host: String
    var publicKey: String
    private(set) var enhancedSecurity: Bool
    private(set) var distinctID: String?
    private(set) var userToken: String?
    private var apiClient: APIClient?
    private(set) var authenticateOptions: AuthenticateOptions?

    /// User instance
    public private(set) lazy var user = User(config: self)

    /// Push instance
    public private(set) lazy var push = Push(config: self)

    let emitter = Emitter()
    private var userTokenExpirationTimer: Timer?

    /// Create SuprSend instance
    /// - Parameters:
    ///   - publicKey: Public key crendentials
    ///   - options: Optional params - host etc.
    public init(
        publicKey: String,
        options: Options? = nil
    ) {
        self.publicKey = publicKey
        self.host = options?.host ?? Constants.defaultHost
        self.enhancedSecurity = options?.enhancedSecurity ?? false
    }

    public func configure(publicKey: String,
                          options: Options? = nil) {
        self.publicKey = publicKey
        self.host = options?.host ?? Constants.defaultHost
        self.enhancedSecurity = options?.enhancedSecurity ?? false
    }
    
    /// Get the APIClient instance for this SuprSend instance.
    /// - Returns: The APIClient instance, or nil if not yet initialized.
    func client() -> APIClient {
        if distinctID == nil {
            logger.warn("[SuprSend]: distinctId is missing. User should be authenticated")
        }

        if let apiClient {
            return apiClient
        }

        let apiClient = APIClient(config: self)

        self.apiClient = apiClient

        return apiClient
    }
    
    func publicClient() -> APIClient {
        if let apiClient {
            return apiClient
        }
        
        let apiClient = APIClient(config: self)
        
        self.apiClient = apiClient
        
        return apiClient
    }

    /// Send an event API request with the given payload.
    /// - Parameters:
    ///   - payload: The event data to send.
    /// - Returns: The response from the API call.
    func eventApi(payload: AnyEncodable) async -> APIResponse {
        let response: APIResponse = await client().request(reqData: .init(path: "v2/event", payload: payload, type: .post))
        switch response.status {
        case .success:
            logger.info("\(response.body?.description ?? "SUCCESS")")
        case .error:
            logger.error("\(response.error?.message ?? "FAILURE")")
        }
        return response
    }

    /// Used to authenticate user. Usually called just after successful login and on reload of loggedin route to re-authenticate loggedin user.
    /// In production env's userToken is mandatory for security purposes.
    /// - Parameters:
    ///   - distinctID: Distinct ID for the device
    ///   - userToken: JWT token for the user
    ///   - options: Authenticate Options
    /// - Returns: Respnose from the API call
    public func identify(
        distinctID: String,
        userToken: String?,
        options: AuthenticateOptions?
    ) async -> APIResponse {

        // other user already present
        guard distinctID != self.distinctID else {
            return .error(
                .init(
                    type: .validation,
                    message: "User already loggedin, reset current user to login new user"
                )
            )
        }

        // updating usertoken for existing user
        if self.apiClient != nil,
            self.distinctID == distinctID,
            self.userToken != userToken
        {
            self.userToken = userToken
            self.apiClient = APIClient(config: self)
            if let refreshUserToken = options?.refreshUserToken {
                self.handleRefreshUserToken(refreshUserToken: refreshUserToken)
            }

            return .success()
        }

        // ignore more than one identify call
        if self.distinctID != nil, self.apiClient != nil {
            return .success()
        }

        self.distinctID = distinctID
        self.userToken = userToken
        self.apiClient = APIClient(config: self)
        self.authenticateOptions = options

        let authenticatedDistinctID = Utils.shared.getLocalStorageData(
            key: Constants.authenticatedDistinctID)

        if let refreshUserToken = options?.refreshUserToken {
            self.handleRefreshUserToken(refreshUserToken: refreshUserToken)
        }

        // already loggedin
        if authenticatedDistinctID == self.distinctID {
            await push.updatePushSubscription()
            return .success()
        }

        // first time login
        let resp = await self.eventApi(
            payload: .init(
                Event(
                    event: "$identify",
                    insertID: UUID().uuidString,
                    time: Date.now.timeIntervalSince1970,
                    distinctID: distinctID,
                    properties: .init(["$identified_id": distinctID])
                )
            )
        )

        switch resp.status {
        case .success:
            await push.updatePushSubscription()
            Utils.shared.setLocalStorageData(
                key: Constants.authenticatedDistinctID, value: distinctID)
        case .error:
            _ = await reset(options: .init(unsubscribePush: false))
        }

        return resp
    }

    /// Check if the user is identified.
    /// - Parameters:
    ///   - checkUserToken: Whether to check for a valid user token.
    /// - Returns: True if the user is identified, false otherwise.
    func isIdentified(checkUserToken: Bool) -> Bool {
        (distinctID != nil) && (checkUserToken ? (userToken != nil) : true)
    }

    /// Track event with given properties
    /// - Parameters:
    ///   - event: The Event name
    ///   - properties: Properties for the event
    /// - Returns: Response from the API call
    public func track(event: String, properties: EventProperty? = nil) async -> APIResponse {
        guard isIdentified(checkUserToken: true) else {
            return .error(
                .init(type: .validation, message: "Identify User First")
            )
        }

        let validatedProperties: EventProperty
        if let properties {
            validatedProperties = Utils.shared.validateObjData(data: properties)
        } else {
            validatedProperties = .init()
        }

        let event = Event(
            event: event,
            insertID: UUID().uuidString,
            time: Date().timeIntervalSince1970,
            distinctID: distinctID ?? String(),
            properties: allProperties(merging: validatedProperties).convertToProperty()
        )

        return await eventApi(payload: .init(event))
    }
    
    func trackPublic(event: String, properties: EventProperty?) async -> APIResponse {
        let validatedProperties: EventProperty
        if let properties {
            validatedProperties = Utils.shared.validateObjData(data: properties)
        } else {
            validatedProperties = .init()
        }
        
        let event = Event(
            event: event,
            insertID: UUID().uuidString,
            time: Date().timeIntervalSince1970,
            distinctID: distinctID ?? String(),
            properties: allProperties(merging: validatedProperties).convertToProperty()
        )
        let response: APIResponse = await publicClient().publicRequest(reqData: .init(path: "v2/event", payload: .init(event), type: .post))
        return response
    }

    /// Handle refresh user token callback
    /// - Parameters:
    ///   - refreshUserToken: Callback to refresh user token
    func handleRefreshUserToken(refreshUserToken: @escaping RefreshTokenCallback) {
        guard let userToken else { return }

        let expiresOn = 0.0
        let now = Date.now.timeIntervalSince1970
        let refreshBefore = 1000.0 * 30.0  // call refresh api before 30sec of expiry

        if expiresOn > now {
            let timeDiff = expiresOn - now - refreshBefore

            if userTokenExpirationTimer != nil {
                userTokenExpirationTimer?.invalidate()
                userTokenExpirationTimer = nil
            }

            userTokenExpirationTimer = Timer.scheduledTimer(
                withTimeInterval: timeDiff, repeats: true
            ) { _ in
                self.timerCallback(refreshUserToken: refreshUserToken)
            }
        }
    }

    /// Timer callback for refresh user token
    /// - Parameters:
    ///   - refreshUserToken: Callback to refresh user token
    private func timerCallback(refreshUserToken: @escaping RefreshTokenCallback) {
        guard let userToken else { return }

        Task {
            let newToken: String?
            let jwtPayload: [String: Any]

            do {
                jwtPayload = try Utils.shared.decode(jwtToken: userToken)
            } catch {
                logger.warning("[SuprSend]: Couldn't decode JWT token")
                return
            }

            do {
                newToken = try await refreshUserToken(
                    userToken,
                    jwtPayload
                )
            } catch {
                // retry fetching token
                do {
                    newToken = try await refreshUserToken(
                        userToken,
                        jwtPayload
                    )
                } catch {
                    newToken = nil
                    logger.warning("[SuprSend]: Couldn't fetch new userToken")
                }
            }

            if let newToken {
                _ = await self.identify(
                    distinctID: self.distinctID ?? String(), userToken: newToken,
                    options: self.authenticateOptions)
            }
        }
    }

    /// Reset the SuprSend instance.
    /// - Parameters:
    ///   - options: Optional reset options
    /// - Returns: The response from the API call.
    public func reset(options: ResetOption? = .init(unsubscribePush: true)) async -> APIResponse {
        let unsubscribePush = options?.unsubscribePush ?? true
        if unsubscribePush {
            await push.removePushSubscription()
        }

        self.apiClient = nil
        self.distinctID = nil
        self.userToken = nil

        Utils.shared.removeLocalStorageData(key: Constants.authenticatedDistinctID)

        if options?.unsubscribePush == true {
            // TODO: Expire timer for reset token
        }

        return .success()
    }

    public func enableLogging() {
        
    }
}

extension SuprSend {
    /// Get the SDK version.
    private var sdkVersion: String {
        (Bundle(for: SuprSend.self).infoDictionary as? [String: String])?[
            "CFBundleShortVersionString"] ?? "2.0.0"
    }

    /// Get the default properties for an event.
    /// - Returns: The default properties.
    private func defaultProperties() -> EventProperty {
        [
            "$os": "iOS",
            "$os_version": "17.0",
            "$sdk_type": "iOS Native",
            "$device_id": "DEVICE_ID",
            "$sdk_version": sdkVersion,
        ]
    }

    /// Get the all properties for an event, merging with default properties.
    /// - Parameters:
    ///   - userProperties: The user-provided properties.
    /// - Returns: The merged properties.
    private func allProperties(merging userProperties: EventProperty?) -> EventProperty {
        if let userProperties {
            defaultProperties().merging(userProperties) { value1, _ in
                value1
            }
        } else {
            defaultProperties()
        }
    }
}
