//
//  SuprSend.swift
//  SuprSend
//
//  Created by Ram Suthar on 24/08/24.
//

import Foundation

@objc public protocol SuprSendDeepLinkDelegate: AnyObject {
    func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool
}

public let shared = SuprSendClient.shared

/// Additional configurations
/// - Parameters:
///   - host: Host URL
///   - appInfo: App name/version to advertise in the user-agent headers. When
///     `nil`, values are auto-detected from `Bundle.main`.
///   - clientUserAgent: Per-field override of the user-agent payload. Useful
///     for wrappers (Flutter/RN) that want to identify themselves.
public class Options: NSObject {
    /// Host URL
    public let host: String?

    /// App info merged into the user-agent payload.
    public let appInfo: AppInfo?

    /// Per-field override of the user-agent payload.
    public let clientUserAgent: ClientUserAgentConfig?

    public init(
        host: String? = nil,
        appInfo: AppInfo? = nil,
        clientUserAgent: ClientUserAgentConfig? = nil
    ) {
        self.host = host
        self.appInfo = appInfo
        self.clientUserAgent = clientUserAgent
    }
}

/// Additional configurations
/// SuprSend iOS Client
public class SuprSendClient: NSObject {
    
    @objc(sharedInstance) public static let shared = SuprSendClient(publicKey: "")

    var host: String
    var publicKey: String
    public private(set) var distinctID: String?

    /// The tenant the SDK currently operates within, sent as `tenant_id` on
    /// every preferences request and applied to newly-initialised feeds that
    /// don't specify their own tenant.
    ///
    /// This is *session* state, not build config: set it at login via
    /// ``identify(distinctID:userToken:tenantId:options:)`` and switch it at
    /// runtime via ``changeTenant(tenantId:pushTokenAction:)``. A per-call `tenantId` (on
    /// ``track(event:properties:tenantId:)``, ``Preferences/Args`` or
    /// ``IFeedOptions``) always overrides this value.
    public private(set) var tenantId: String?

    var deviceToken: String?
    private(set) var userToken: String?
    private var apiClient: APIClient?
    private(set) var authenticateOptions: AuthenticateOptions?

    /// Fully-resolved user-agent payload sent on every request as JSON in the
    /// `X-Suprsend-Client-User-Agent` header.
    private(set) var clientUserAgent: ClientUserAgentConfig
    /// Compact string form sent on every request in the `X-Suprsend-User-Agent`
    /// header.
    private(set) var userAgent: String
    /// Pre-encoded JSON form of ``clientUserAgent`` so `APIClient` doesn't
    /// re-encode on every request.
    private(set) var clientUserAgentJSON: String

    /// User instance
    public private(set) lazy var user = User(config: self)

    /// Push instance
    public private(set) lazy var push = Push(config: self)
    
    /// Preferences instance
    public private(set) lazy var preferences = Preferences(config: self)
    
    /// Feeds instance
    public private(set) lazy var feeds = FeedsFactory(config: self)

    public let emitter = Emitter()

    private(set) var urlDelegate: SuprSendDeepLinkDelegate?

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
        let resolvedUA = buildClientUserAgent(
            appInfo: options?.appInfo,
            override: options?.clientUserAgent
        )
        self.clientUserAgent = resolvedUA
        self.userAgent = buildUserAgent(resolvedUA)
        self.clientUserAgentJSON = encodeClientUserAgent(resolvedUA)
    }

    @objc public func configure(publicKey: String,
                                options: Options? = nil,
                                urlDelegate: SuprSendDeepLinkDelegate? = nil) {
        self.publicKey = publicKey
        self.host = options?.host ?? Constants.defaultHost
        self.urlDelegate = urlDelegate
        self.push.delegate = urlDelegate as? SuprSendPushNotificationDelegate
        let resolvedUA = buildClientUserAgent(
            appInfo: options?.appInfo,
            override: options?.clientUserAgent
        )
        self.clientUserAgent = resolvedUA
        self.userAgent = buildUserAgent(resolvedUA)
        self.clientUserAgentJSON = encodeClientUserAgent(resolvedUA)

        // Now that the public key is set, retry any events queued before it was
        // available — e.g. a notification tap handled on a cold (killed-state)
        // launch, where this configure() runs after the native push callback.
        self.push.flushPendingEvents()
    }
    
    @objc public func setDeepLinkDelegate(_ urlDelegate: SuprSendDeepLinkDelegate) {
        self.urlDelegate = urlDelegate
    }
    
    /// Get the APIClient instance for this SuprSend instance.
    /// - Returns: The APIClient instance, or nil if not yet initialized.
    func client() -> APIClient {
        if distinctID == nil {
            logger.warning("[SuprSend]: distinctId is missing. User should be authenticated")
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
    ///   - tenantId: Tenant the user is logging into. Stored as the global
    ///     ``tenantId`` and applied to subsequent preferences/feed calls. When
    ///     the user's token scopes multiple tenants, switch between them at
    ///     runtime with ``changeTenant(tenantId:pushTokenAction:)`` — no re-identify needed.
    ///   - options: Authenticate Options
    /// - Returns: Respnose from the API call
    public func identify(
        distinctID: String,
        userToken: String? = nil,
        tenantId: String? = nil,
        options: AuthenticateOptions? = nil
    ) async -> APIResponse {

        // other user already present
        guard (self.distinctID == nil || distinctID == self.distinctID) else {
            return .error(
                .init(
                    type: .validation,
                    message: "User already loggedin, reset current user to login new user"
                )
            )
        }

        // Set the tenant for this session before any request goes out. Placed
        // after the "other user" guard so a rejected identify doesn't mutate
        // the current user's tenant. `nil` (e.g. token-refresh re-identify)
        // leaves the existing tenant untouched.
        if let tenantId {
            self.tenantId = tenantId
        }

        // updating usertoken for existing user
        if self.apiClient != nil,
            self.distinctID == distinctID,
            self.userToken != userToken
        {
            // `APIClient` reads the token live on every request, so it doesn't
            // need rebuilding — and keeping the same instance keeps its
            // in-flight refresh coalescer alive for the whole session.
            self.userToken = userToken
            // `nil` keeps the existing options (this is how the internal token
            // refresh re-identifies); pass options to replace them.
            if let options {
                self.authenticateOptions = options
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
                    time: Utils.shared.epochMs(),
                    distinctID: distinctID,
                    properties: .init(["$identified_id": distinctID]),
                    tenantId: self.tenantId
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
    public func isIdentified(checkUserToken: Bool) -> Bool {
        (distinctID != nil) && (checkUserToken ? (userToken != nil) : true)
    }

    /// Switch the active tenant after login.
    ///
    /// Intended for users whose token scopes multiple tenants (a `tenant_id`
    /// array): identify once, then call this to move between them without
    /// resetting the session. Updates the global ``tenantId`` used by
    /// subsequent events, preferences requests and newly-initialised feeds.
    ///
    /// - Note: Already-running feed instances keep the tenant they were
    ///   initialised with — re-initialise a feed (via ``feeds``) to have it
    ///   reflect the new tenant. Re-fetch preferences (``Preferences/getPreferences(args:)``)
    ///   to load the new tenant's data.
    /// - Parameters:
    ///   - tenantId: The tenant to switch to.
    ///   - pushTokenAction: What to do with the device's push token. `.none`
    ///     (default) leaves it attached to the current tenant; `.copy` attaches
    ///     it to the new tenant as well; `.move` detaches it from the current
    ///     tenant and attaches it to the new one. A device with no push token
    ///     switches tenant successfully regardless.
    /// - Returns: `.success()` once the tenant is switched. With `.copy` or
    ///   `.move`, a failure to attach the token to the new tenant restores the
    ///   previous tenant (re-attaching the token to it for `.move`) and returns
    ///   that error, so the session never ends up on a tenant without the
    ///   token the caller asked for.
    @objc public func changeTenant(
        tenantId: String,
        pushTokenAction: PushTokenAction = .none
    ) async -> APIResponse {
        guard !tenantId.isEmpty else {
            return .error(.init(type: .validation, message: "tenantId is missing or invalid"))
        }

        let identified = isIdentified(checkUserToken: false)
        if !identified {
            logger.warning("[SuprSend]: changeTenant called before identify. Tenant will apply once a user is identified.")
        }

        let oldTenantId = self.tenantId
        // Only touch the token when there's something to do: an identified
        // user, an actual tenant change, and a token on this device.
        let attachPush = pushTokenAction != .none
            && identified
            && oldTenantId != tenantId
            && push.pushSubscribed()

        if attachPush, pushTokenAction == .move {
            // Detach while still scoped to the old tenant.
            let removeResp = await push.removePushSubscription()
            if removeResp.status == .error {
                return removeResp
            }
        }

        self.tenantId = tenantId

        if attachPush {
            // Attach under the new tenant. On failure roll the session back so
            // the caller isn't left on a tenant the token never reached.
            let updateResp = await push.updatePushSubscription()
            if updateResp.status == .error {
                self.tenantId = oldTenantId
                if pushTokenAction == .move {
                    await push.updatePushSubscription()
                }
                return updateResp
            }
        }

        return .success()
    }

    /// Track event with given properties
    /// - Parameters:
    ///   - event: The Event name
    ///   - properties: Properties for the event
    ///   - tenantId: Tenant to attribute this single event to. When `nil` the
    ///     global ``tenantId`` is used. Scoping one event this way does not
    ///     change the session tenant — use ``changeTenant(tenantId:pushTokenAction:)`` for that.
    /// - Returns: Response from the API call
    public func track(
        event: String,
        properties: EventProperty? = nil,
        tenantId: String? = nil
    ) async -> APIResponse {
        let validatedProperties: EventProperty
        if let properties {
            validatedProperties = Utils.shared.validateObjData(data: properties)
        } else {
            validatedProperties = .init()
        }

        let event = Event(
            event: event,
            insertID: UUID().uuidString,
            time: Utils.shared.epochMs(),
            distinctID: distinctID ?? String(),
            properties: validatedProperties.convertToProperty(),
            tenantId: tenantId ?? self.tenantId
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

        // Public notification events ($notification_clicked/_delivered/_dismiss)
        // omit tenant_id — the tenant is resolved server-side from the
        // notification id, and this path can run unidentified (Notification
        // Service Extension / cold start) where no reliable tenant exists.
        let event = Event(
            event: event,
            insertID: UUID().uuidString,
            time: Utils.shared.epochMs(),
            distinctID: distinctID ?? String(),
            properties: validatedProperties.convertToProperty(),
            tenantId: nil,
            emitsTenant: false
        )
        let response: APIResponse = await publicClient().publicRequest(reqData: .init(path: "v2/event", payload: .init(event), type: .post))
        return response
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
        self.tenantId = nil

        Utils.shared.removeLocalStorageData(key: Constants.authenticatedDistinctID)

        if !feeds.feedInstances.isEmpty {
            feeds.removeAll()
        }

        return .success()
    }

    @objc public func enableLogging() {
        logger.enableLogging()
    }
}
