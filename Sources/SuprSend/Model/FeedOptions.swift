//
//  File.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/07/25.
//

import Foundation

/// Configuration options
/// - Parameters:
///   - host: Host URL
public class IFeedOptions: NSObject {
    /// Host URL
    public let tenantId: String?
    
    public let pageSize: UInt?
    
    public let stores: [IStore]?
    
    public let host: FeedHost?
    
    public init(
        tenantId: String?,
        pageSize: UInt?,
        stores: [IStore]? = nil,
        host: FeedHost?
    ) {
        self.tenantId = tenantId
        self.pageSize = pageSize
        self.stores = stores
        self.host = host
    }
}

public class IStoreQuery: NSObject, Codable {
    public let tags: [String]?
    public let categories: [String]?
    public let read: Bool?
    public let archived: Bool?
    
    init(tags: [String]?, categories: [String]?, read: Bool?, archived: Bool?) {
        self.tags = tags
        self.categories = categories
        self.read = read
        self.archived = archived
    }
}

public class IStore: NSObject, Codable {
    public let storeId: String
    
    public let label: String
    
    public let query: IStoreQuery?
    
    init(storeId: String, label: String, query: IStoreQuery? = nil) {
        self.storeId = storeId
        self.label = label
        self.query = query
    }
}

public class FeedHost: NSObject {
    public let socketHost: String?
    public let apiHost: String?
    
    public init(socketHost: String?, apiHost: String?) {
        self.socketHost = socketHost
        self.apiHost = apiHost
    }
}

public class INotificationStore: NSObject {
    public let notifications: [IRemoteNotification]
    public let store: IStore
    public let pageInfo: IPageInfo
    public let meta: [String: String]
    public let apiStatus: APIResponseStatus
    public let isFirstFetch: Bool
    
    init(
        notifications: [IRemoteNotification],
        store: IStore,
        pageInfo: IPageInfo,
        meta: [String : String],
        apiStatus: APIResponseStatus,
        isFirstFetch: Bool
    ) {
        self.notifications = notifications
        self.store = store
        self.pageInfo = pageInfo
        self.meta = meta
        self.apiStatus = apiStatus
        self.isFirstFetch = isFirstFetch
    }
    
    func with(apiStatus: APIResponseStatus) -> INotificationStore {
        .init(
            notifications: notifications,
            store: store,
            pageInfo: pageInfo,
            meta: meta,
            apiStatus: apiStatus,
            isFirstFetch: isFirstFetch
        )
    }
    
    func with(meta: [String: String]?) -> INotificationStore {
        .init(
            notifications: notifications,
            store: store,
            pageInfo: pageInfo,
            meta: meta ?? self.meta,
            apiStatus: apiStatus,
            isFirstFetch: isFirstFetch
        )
    }
    
    func with(notifications: [IRemoteNotification]) -> INotificationStore {
        .init(
            notifications: notifications,
            store: store,
            pageInfo: pageInfo,
            meta: meta,
            apiStatus: apiStatus,
            isFirstFetch: isFirstFetch
        )
    }
}

public class IFeedData: NSObject {
    public let notifications: [IRemoteNotification]
    public let store: IStore
    public let pageInfo: IPageInfo
    public let meta: [String: String]
    public let apiStatus: APIResponseStatus
    
    init(
        notifications: [IRemoteNotification],
        store: IStore,
        pageInfo: IPageInfo,
        meta: [String : String],
        apiStatus: APIResponseStatus
    ) {
        self.notifications = notifications
        self.store = store
        self.pageInfo = pageInfo
        self.meta = meta
        self.apiStatus = apiStatus
    }
}

public enum InboxEmitterEvents {
    case newNotification(IRemoteNotification)
    case storeUpdate(IFeedData)
}
