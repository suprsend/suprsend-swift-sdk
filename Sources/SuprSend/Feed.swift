//
//  Feed.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/07/25.
//

import Foundation
import Combine

private enum FeedConstants {
    static let pageSize: UInt = 20
    static let tenantId = "default"
    static let maxPageSize: UInt = 100
    static let store = IStore(storeId: "$suprsend_default_store", label: "")
}

/// A class responsible for handling inbox feed.
public class Feed {
    /// The configuration instance used to manage user data.
    private let config: SuprSendClient
    
    private let feedOptions: IFeedOptions
    
    private var store: CurrentValueSubject<INotificationStore, Never>
    
    private var socket: SocketClient?
    
    private var expiryTimerId: Timer?
    
    public var emitter: PassthroughSubject<InboxEmitterEvents, Never> = .init()
    
    private var cancellables = Set<AnyCancellable>()
    
    public var data: IFeedData {
        let storeData = store.value
        
        return .init(
            notifications: storeData.notifications,
            store: storeData.store,
            pageInfo: storeData.pageInfo,
            meta: storeData.meta,
            apiStatus: storeData.apiStatus
        )
    }
    
    /// Initializes a new `Feed` instance with the given configuration.
    /// - Parameter config: The configuration instance to use.
    init(config: SuprSendClient, options: IFeedOptions? = nil) {
        self.config = config
        
        // Set options
        var pageSize = FeedConstants.pageSize
        if let pageSizeOption = options?.pageSize,
           1...FeedConstants.maxPageSize ~= pageSizeOption {
            pageSize = pageSizeOption
        }
        self.feedOptions = .init(
            tenantId: options?.tenantId ?? FeedConstants.tenantId,
            pageSize: pageSize,
            stores: Self.validatedStores(options?.stores),
            host: options?.host
        )
        
        // Create feed store
        self.store = .init(
            .init(
                notifications: [],
                store: options?.stores?.first ?? FeedConstants.store,
                pageInfo: .init(
                    total: .zero,
                    hasMore: false,
                    pageSize: FeedConstants.pageSize
                ),
                meta: ["badge": "0"],
                apiStatus: .initial,
                isFirstFetch: true
            )
        )
    }
    
    func reset() {
        store.send(.init(
            notifications: [],
            store: feedOptions.stores?.first ?? FeedConstants.store,
            pageInfo: .init(
                total: .zero,
                hasMore: false,
                pageSize: FeedConstants.pageSize
            ),
            meta: ["badge": "0"],
            apiStatus: .initial,
            isFirstFetch: true
        ))
        emitter.send(.storeUpdate(self.data))
        
        if (expiryTimerId != nil) {
            expiryTimerId?.invalidate()
            expiryTimerId = nil
        }
    }
    
    func remove() {
        reset()
        emitter.send(completion: .finished)
//        socket?.disconnect()
        config.feeds.removeInstance(self)
    }
    
    private static func validatedStores(_ stores: [IStore]?) -> [IStore]? {
        guard let stores = stores else {
            return stores
        }
        
        guard stores.isEmpty else {
            logger.warning("SuprSend: stores should be an array of objects")
            return stores
        }
        
        var validatedStores: [IStore] = []
        
        stores.forEach(
            { store in
                guard store.storeId.isEmpty else {
                    logger.warning(
                        "SuprSend: storeId is mandatory for each store. Ignoring store without storeId"
                    )
                    return
                }
                let query = store.query
                
                validatedStores
                    .append(
                        .init(
                            storeId: store.storeId,
                            label: store.label.isEmpty ? store.storeId : store.label,
                            query: query
                        )
                    )
                
            })
        return validatedStores
    }
}

// MARK: - API Calls
extension Feed {
    
    private var requestInprogress: Bool {
        let storeData = store.value
        
        return [
            .loading,
            .fetchingMore,
        ].contains(storeData.apiStatus)
    }
    
    public func fetchCount() async -> FeedCountAPIResponse {
        let queryParams: [String: Any?] = [
            "distinct_id": config.distinctID,
            "tenant_id": feedOptions.tenantId,
            "stores": feedOptions.stores != nil
            ? storesQueryParamObj(feedOptions.stores)
            : nil,
        ]
        
        let url = getUrl(path: "notifications_count", qp: queryParams)
        
        let response: FeedCountAPIResponse = await config.client().request(
            reqData: .init(path: url.absoluteString, payload: nil, type: .get)
        )
        
        if (response.status == .success) {
            let meta = ["badge": "\(response.body?.badge ?? 0)"]
            store.send(store.value.with(meta: meta))
        }
        
        emitter.send(.storeUpdate(self.data))
        return response
    }
    
    // TODO: support other stores and pages
    public func fetch(options: IInboxFetchOptions? = nil) async -> FeedAPIResponse {
        var storeData = store.value
        
        if requestInprogress {
            return .error(.init(type: .validation, message: "Already fetching data"))
        }
        
        let pageSize = options?.pageSize ?? feedOptions.pageSize
        
        if (!storeData.isFirstFetch) {
            store.send(storeData.with(apiStatus: .fetchingMore))
        } else {
            store.send(storeData.with(apiStatus: .loading))
            await fetchCount()
        }
        storeData = store.value
        emitter.send(.storeUpdate(self.data))
        
        var queryParams: [String: Any?] = [
            "distinct_id": config.distinctID,
            "tenant_id": feedOptions.tenantId,
            "page_size": pageSize,
            "store": storeData.store.storeId != FeedConstants.store.storeId
            ? storeQueryParamObj(storeData.store)
            : nil,
        ]
        
        if (storeData.notifications.count > 0) {
            let lastNotification =
            storeData.notifications[storeData.notifications.count - 1]
            queryParams["search_after"] = [
                lastNotification.is_pinned,
                lastNotification.created_on,
            ]
        } else {
            queryParams["search_after"] = []
        }
        
        let url = getUrl(path: "notifications", qp: queryParams)
        
        let response: FeedAPIResponse = await config.client().request(
            reqData: .init(path: url.absoluteString, payload: nil, type: .get)
        )
        
        if (response.status == .error) {
            store.send(store.value.with(apiStatus: .error))
            emitter.send(.storeUpdate(self.data))
            return response
        }
        
        var notifications = storeData.notifications
        let results = response.body?.results ?? []
        if storeData.isFirstFetch {
            notifications = results
        } else  {
            notifications.append(contentsOf: results)
        }
        
        let hasMore = (response.body?.meta?.current_page ?? 0) < (response.body?.meta?.total_pages ?? 0)
        let pageInfo = IPageInfo.init(
            total: response.body?.meta?.total_count ?? 0,
            hasMore: hasMore,
            pageSize: storeData.pageInfo.pageSize
        )
        
        store
            .send(
                .init(
                    notifications: notifications,
                    store: storeData.store,
                    pageInfo: pageInfo,
                    meta: storeData.meta,
                    apiStatus: .success,
                    isFirstFetch: false
                )
            )
        
        emitter.send(.storeUpdate(self.data))
        
        startExpiryTimer()
        
        return response
    }
    
    // TODO: support other stores
    public func fetchNextPage() async -> FeedAPIResponse? {
        let storeData = store.value
        
        guard storeData.pageInfo.hasMore == true else {
            return .error(ResponseError(type: .validation, message: "No more pages to fetch"))
        }
        
        return await fetch()
    }
    
    public func fetchDetails(notificationId: String) async -> FeedDetailAPIResponse {
        let url = getUrl(path: "notifications/\(notificationId)", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        return await config
            .client()
            .request(
                reqData: .init(path: url.absoluteString, payload: nil, type: .get)
            )
    }
    
    public func markAsSeen(notificationId: String) async -> APIResponse {
        let storeData = store.value
        var alreadyUpdated = false
        
        store.send(storeData.with(
            notifications: storeData.notifications.map({ notification in
                if (notification.n_id == notificationId) {
                    if (notification.seen_on == nil) {
                        return notification
                            .with(seen_on: Date.now.timeIntervalSince1970)
                    } else {
                        alreadyUpdated = true
                    }
                }
                return notification
            }),
        ))
        
        if (alreadyUpdated) {
            return .success()
        }
        
        let url = getUrl(path: "notifications/\(notificationId)/seen", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    public func markAsRead(notificationId: String) async -> APIResponse {
        let storeData = store.value
        var alreadyUpdated = false
        
        store.send(storeData.with(
            notifications: storeData.notifications.map({ notification in
                if (notification.n_id == notificationId) {
                    if (notification.read_on == nil) {
                        return notification
                            .with(read_on: Date.now.timeIntervalSince1970)
                    } else {
                        alreadyUpdated = true
                    }
                }
                return notification
            }),
        ))
        
        if (alreadyUpdated) {
            return .success()
        }
        
        let url = getUrl(path: "notifications/\(notificationId)/read", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    public func markAsUnread(notificationId: String) async -> APIResponse {
        let storeData = store.value
        var alreadyUpdated = false
        
        store.send(storeData.with(
            notifications: storeData.notifications.map({ notification in
                if (notification.n_id == notificationId) {
                    if (notification.read_on != nil) {
                        return notification
                            .with(read_on: nil)
                    } else {
                        alreadyUpdated = true
                    }
                }
                return notification
            }),
        ))
        
        if (alreadyUpdated) {
            return .success()
        }
        
        let url = getUrl(path: "notifications/\(notificationId)/unread", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    // TODO: improve logic for already interacted cases
    public func markAsInteracted(notificationId: String) async -> APIResponse {
        let storeData = store.value
        
        store.send(storeData.with(
            notifications: storeData.notifications.map({ notification in
                if (notification.n_id == notificationId) {
                    if (notification.interacted_on == nil) {
                        return notification
                            .with(interacted_on: Date.now.timeIntervalSince1970)
                    }
                    if (notification.read_on == nil) {
                        return notification
                            .with(read_on: Date.now.timeIntervalSince1970)
                    }
                }
                return notification
            }),
        ))
        
        let url = getUrl(path: "notifications/\(notificationId)/interacted", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    public func markAsArchived(notificationId: String) async -> APIResponse {
        let storeData = store.value
        var alreadyUpdated = false
        
        store.send(storeData.with(
            notifications: storeData.notifications.filter({ notification in
                if (notification.n_id == notificationId) {
                    alreadyUpdated = notification.archived == true
                    return false
                }
                return true
            }),
        ))
        
        if (alreadyUpdated) {
            return .success()
        }
        
        let url = getUrl(path: "notifications/\(notificationId)/archive", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    public func markBulkAsSeen(notificationIds: [String]) async -> APIResponse {
        let storeData = store.value
        
        store.send(storeData.with(
            notifications: storeData.notifications.map({ notification in
                if (notificationIds.contains(notification.n_id)) {
                    if (notification.seen_on == nil) {
                        return notification
                            .with(seen_on: Date.now.timeIntervalSince1970)
                    }
                }
                return notification
            }),
        ))
        
        let url = getUrl(path: "bulk/notifications/seen", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: .init(["notification_ids": notificationIds]),
                    type: .post
                )
            )
    }
    
    public func resetBadgeCount() async -> APIResponse {
        let storeData = store.value
        var meta = storeData.meta
        meta["badge"] = "0"
        
        // optimistic update
        store.send(storeData.with(meta: meta))
        
        let url = getUrl(path: "reset_bell_count", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID
        ])
        
        emitter.send(.storeUpdate(self.data))
        
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
    
    public func markAllAsRead() async -> APIResponse {
        let storeData = store.value
        var meta = storeData.meta
        meta["badge"] = "0"
        
        store.send(storeData.with(
            notifications: storeData
                .with(meta: meta)
                .notifications.map({ notification in
                    if (notification.read_on == nil) {
                        return notification
                            .with(read_on: Date.now.timeIntervalSince1970)
                    }
                    return notification
                }),
        ))
        
        let url = getUrl(path: "mark_all_read", qp: [
            "tenant_id": feedOptions.tenantId,
            "distinct_id": config.distinctID,
        ])
        
        emitter.send(.storeUpdate(self.data))
        
        return await config
            .client()
            .request(
                reqData: .init(
                    path: url.absoluteString,
                    payload: nil,
                    type: .patch
                )
            )
    }
}

// MARK: - Expiry Timer
extension Feed {
    private func startExpiryTimer() {
        if (expiryTimerId != nil) {
            return
        }
        expiryTimerId =
            .scheduledTimer(timeInterval: 30000, target: self, selector: #selector(removeExpiredFeed), userInfo: nil, repeats: true)
    }
    
    @objc private func removeExpiredFeed() async {
        let storeData = store.value
        var hasExpired = false
        
        let notifications = storeData.notifications.filter(
            { (notification: IRemoteNotification) in
                let expired = notification.expiry != nil
                ? Date.now > Date(timeIntervalSince1970: notification.expiry!)
                : false
                if (expired) {
                    hasExpired = true
                    return false
                } else {
                    return true
                }
            }
        )
        
        if (hasExpired) {
            store.send(store.value.with(notifications: notifications))
            await fetchCount()
            emitter.send(.storeUpdate(self.data))
        }
    }
}

// MARK: - URL & Query Params
extension Feed {
    
    private func storeQueryParamObj(_ store: IStore) -> IStore {
        .init(
            storeId: store.storeId,
            label: store.label,
            query: .init(
                tags: store.query?.tags ?? [],
                categories: store.query?.categories ?? [],
                read: store.query?.read,
                archived: store.query?.archived
            )
        )
    }
    
    private func storesQueryParamObj(_ stores: [IStore]?) -> [IStore]? {
        let apiStores = stores?.map({ store in
            return storeQueryParamObj(store)
        })
        
        return apiStores
    }
    
    private func validateQueryParams(_ queryParams: [String: Any?]) -> [String: String] {
        var validatedParams: [String: String] = [:]
        for (key, paramValue) in queryParams {
            do {
                guard let value = paramValue as? Encodable else {
                    continue
                }
                
                if let string = value as? String {
                    validatedParams[key] = string
                        .addingPercentEncoding(
                            withAllowedCharacters: .urlQueryAllowed
                        )
                } else {
                    let encodedValue = try JSONEncoder().encode(value)
                    validatedParams[key] = String(data: encodedValue, encoding: .utf8)
                }
            } catch {
                logger.warning(error.localizedDescription)
            }
        }
        return validatedParams
    }
    
    private func getUrl(path: String, qp: [String: Any?]) -> URL {
        let urlPath = "\(feedOptions.host?.apiHost ?? "")/v1/feed/\(path)"
        let validatedQueryParams = validateQueryParams(qp)
        let queryParams = validatedQueryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        var urlComponents = URLComponents(string: urlPath)!
        if !queryParams.isEmpty {
            urlComponents.queryItems = queryParams
        }
        return urlComponents.url!
    }
}

// MARK: - Filter, Sort
extension Feed {
    
    private func notificationBelongToStore(
        notification: IRemoteNotification,
        store: IStore?
    ) -> Bool {
        let notifRead = notification.read_on != nil
        let notifArchived = notification.archived
        let notifTags = notification.tags
        let notifCategory = notification.n_category
        
        let storeRead = store?.query?.read
        let storeArchived = store?.query?.archived
        let storeTags = store?.query?.tags
        let storeCategories = store?.query?.categories
        
        let sameRead =  storeRead == nil || notifRead == storeRead
        let sameArchived = (notifArchived ?? false) == (storeArchived ?? false)
        var sameTags = false
        var sameCategory = false
        
        if let storeTags,
           !storeTags.isEmpty {
            storeTags.forEach { tag in
                if notifTags?.contains(tag) == true {
                    sameTags = true
                }
            }
        } else {
            sameTags = true
        }
        
        if let storeCategories,
           !storeCategories.isEmpty {
            if storeCategories.contains(notifCategory) {
                sameCategory = true
            }
        } else {
            sameCategory = true
        }
        
        return sameRead && sameTags && sameCategory && sameArchived
    }
    
    
    private func orderNotificationsBasedOnPinFlag(
        newNotification: IRemoteNotification,
        existingNotifications: [IRemoteNotification]
    ) -> [IRemoteNotification] {
        // if pinned notification add new notification append at start else at end of pinned notifications
        if (newNotification.is_pinned) {
            return [newNotification] + existingNotifications
        } else {
            var addedNotification = false
            var notifications: [IRemoteNotification] = []
            
            existingNotifications.forEach { notification in
                if (notification.is_pinned) {
                    notifications.append(notification)
                } else {
                    if (addedNotification) {
                        notifications.append(notification)
                    } else {
                        notifications.append(newNotification)
                        notifications.append(notification)
                        addedNotification = true
                    }
                }
            }
            
            if !addedNotification {
                return existingNotifications + [newNotification]
            }
            
            return notifications
        }
    }
}

// MARK: - Web Socket
extension Feed {
    
    public func initializeSocketConnection() {
        guard socket == nil else {
            return
        }
        
        guard let host = feedOptions.host?.socketHost else {
            return
        }
        
        var headers: [String: String] = [:]
        headers["authorization"] = config.publicKey
        headers["x-ss-signature"] = config.userToken
        headers["distinct_id"] = config.distinctID
        headers["tenant_id"] = feedOptions.tenantId
        headers["schema"] = "1"
        
        socket = SocketClient(serverURL: host, headers: headers)
        socket?.connect()
        
        initializeSocketEvents()
    }
    
    private func initializeSocketEvents() {
        socket?.$receivedMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                let lastMessage = messages.last
                
                switch lastMessage?.event {
                case .newNotification:
                    Task {
                        await self?.handleNewNotificationSocketEvent(data: lastMessage?.data)
                    }
                case .notificationUpdate:
                    Task {
                        await self?.handleNoticationUpdateSocketEvent(data: lastMessage?.data)
                    }
                case .bulklNotificationUpdate:
                    Task {
                        await self?.handleBulkNotificationUpdateSocketEvent(
                            data: lastMessage?.data
                        )
                    }
                case .resetBadge:
                    self?.handleResetBadge()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleResetBadge() {
        let storeData = store.value
        var meta = storeData.meta
        meta["badge"] = "0"
        
        // optimistic update
        store.send(storeData.with(meta: meta))
        
        emitter.send(.storeUpdate(self.data))
    }
    
    private func handleNewNotificationSocketEvent(data: [String: AnyDecodable]?) async {
        guard let nid = data?["n_id"],
            case .string(let notificationId) = nid else { return }
        
        let response = await fetchDetails(notificationId: notificationId)
        if (response.status == .error) {
            return
        }
        
        guard let newNotificationData = response.body else {
            return
        }
        
        let storeData = store.value
        var emitNewNotificationEvent = false
        
        var newMetaData = storeData.meta
        
        if notificationBelongToStore(notification: newNotificationData, store: storeData.store) {
            emitNewNotificationEvent = true
            store.send(
                store.value.with(
                    notifications: orderNotificationsBasedOnPinFlag(
                        newNotification: newNotificationData,
                        existingNotifications: store.value.notifications
                    )
                )
            )
        }
        
        feedOptions.stores?.map { store in
            if (notificationBelongToStore(notification: newNotificationData, store: store)) {
                emitNewNotificationEvent = true
                newMetaData[store.storeId] = String((Int(storeData.meta[store.storeId] ?? "0") ?? 0) + 1)
            }
        }
        
        // update overall badge count as well if it belongs any of store current store
        let badge = newMetaData["badge"]
        let plusBadge = String((Int(badge ?? "0") ?? 0) + 1)
        newMetaData["badge"] = emitNewNotificationEvent ? plusBadge : badge
        store.send(store.value.with(meta: newMetaData))
        
        if (emitNewNotificationEvent) {
            emitter.send(.newNotification(newNotificationData))
        }
        
        emitter.send(.storeUpdate(self.data))
    }

    
    private func handleNoticationUpdateSocketEvent(data: [String: AnyDecodable]?) async {
        guard let nid = data?["n_id"],
              case .string(let notificationId) = nid else { return }
        
        async let details = fetchDetails(notificationId: notificationId)
        async let count = fetchCount()
        
        let (detailResponse, countResponse) = await (details, count)
        
        let storeData = store.value
        
        guard detailResponse.status == .success,
            let newNotificationData: IRemoteNotification = detailResponse.body else {
            return
        }
        
        let notificationPresent = storeData.notifications.contains(where: { $0.n_id == newNotificationData.n_id })
        let notificationBelongsToStore = notificationBelongToStore(
            notification: newNotificationData,
            store: storeData.store
        )
        
        if (notificationBelongsToStore) {
            if (!notificationPresent) {
                // Insert new notification
                store.send(
                    store.value.with(
                        notifications: orderNotificationsBasedOnPinFlag(
                            newNotification: newNotificationData,
                            existingNotifications: store.value.notifications
                        )
                    )
                )
            } else {
                // Update existing notification data
                store.send(
                    store.value.with(
                        notifications: storeData.notifications.compactMap {
                            $0.n_id == newNotificationData.n_id ? newNotificationData : $0
                        })
                )
            }
        } else {
            // Filter out notification
            store.send(
                store.value.with(
                    notifications: storeData.notifications.filter {
                        $0.n_id != newNotificationData.n_id
                    })
            )
        }
        
        emitter.send(.storeUpdate(self.data))
    }
    
    
    private func handleBulkNotificationUpdateSocketEvent(data: [String: AnyDecodable]?) async {
        guard let data else {
            return
        }
        
        let storeData = store.value
        let action = data["action"]
        let notificationIds = data["notification_ids"]
        
        guard case let .string(actionType) = action else {
            return
        }
        
        if actionType == "read",
           case let .string(ids) = notificationIds,
            ids == "all" {
            var meta = storeData.meta
            meta["badge"] = "0"
            
            store.send(storeData.with(meta: meta)
                .with(notifications: storeData
                    .with(meta: meta)
                    .notifications.map({ notification in
                        if (notification.read_on == nil) {
                            notification
                                .with(read_on: Date.now.timeIntervalSince1970)
                        } else {
                            notification
                        }
                    }),
                ))
        }
        
        if actionType == "seen",
           case let .array(idArray) = notificationIds {
            let ids: [String] = idArray.compactMap { value in
                if case let .string(id) = value {
                    id
                } else {
                    nil
                }
            }
            
            store.send(storeData.with(
                notifications: storeData
                    .notifications.map({ notification in
                        if (ids.contains(notification.n_id)) {
                            notification
                                .with(seen_on: Date.now.timeIntervalSince1970)
                        } else {
                            notification
                        }
                    }),
            ))
        }
        
        emitter.send(.storeUpdate(self.data))
    }

}
