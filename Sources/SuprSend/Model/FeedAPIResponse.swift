//
//  File.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/07/25.
//

import Foundation

public struct FeedAPIResponse: Response {
    /// The status of the API response
    public let status: ResponseStatus
    
    /// The HTTP status code of the API response (optional)
    public let statusCode: StatusCode?
    
    /// The body of the API response (optional)
    public let body: FeedData?
    
    /// An error message if any (optional)
    public let error: ResponseError?
    
    /// Initializes a `PreferenceAPIResponse` instance
    ///
    /// - Parameters:
    ///   - status: The status of the API response.
    ///   - statusCode: The HTTP status code of the API response (optional).
    ///   - body: The body of the API response (optional).
    ///   - error: An error message if any (optional).
    public init(
        status: ResponseStatus, statusCode: StatusCode?, body: FeedData?,
        error: ResponseError?
    ) {
        self.status = status
        self.statusCode = statusCode
        self.body = body
        self.error = error
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = (try? container.decodeIfPresent(ResponseStatus.self, forKey: .status)) ?? .success
        self.statusCode = try container.decodeIfPresent(StatusCode.self, forKey: .statusCode)
        self.error = try container.decodeIfPresent(ResponseError.self, forKey: .error)
        
        self.body = try FeedData(from: decoder)
    }
}

public class FeedData: NSObject, Codable {
    public let results: [IRemoteNotification]?
    public let meta: FeedMeta?
}

public class FeedMeta: NSObject, Codable {
    public let total_count: UInt?
    public let current_page: UInt?
    public let total_pages: UInt?
}

public class IActionObject: NSObject, Codable {
    public let name: String
    public let url: String
    public let open_in_new_tab: Bool?
    
    init(name: String, url: String, open_in_new_tab: Bool?) {
        self.name = name
        self.url = url
        self.open_in_new_tab = open_in_new_tab
    }
}

public class IAvatarObject: NSObject, Codable {
    public let action_url: String?
    public let avatar_url: String
    
    init(action_url: String?, avatar_url: String) {
        self.action_url = action_url
        self.avatar_url = avatar_url
    }
}

public class ISubTextObject: NSObject, Codable {
    public let action_url: String?
    public let text: String
    
    init(action_url: String?, text: String) {
        self.action_url = action_url
        self.text = text
    }
}

public class IRemoteNotificationMessage: NSObject, Codable {
    public let header: String?
    public let schema: String
    public let text: String
    public let url: String?
    public let open_in_new_tab: Bool?
    public let extra_data: String?
    public let actions: [IActionObject]?
    public let avatar: IAvatarObject?
    public let subtext: ISubTextObject?
    
    init(
        header: String?,
        schema: String,
        text: String,
        url: String?,
        open_in_new_tab: Bool?,
        extra_data: String?,
        actions: [IActionObject]?,
        avatar: IAvatarObject?,
        subtext: ISubTextObject?
    ) {
        self.header = header
        self.schema = schema
        self.text = text
        self.url = url
        self.open_in_new_tab = open_in_new_tab
        self.extra_data = extra_data
        self.actions = actions
        self.avatar = avatar
        self.subtext = subtext
    }
}

public class IRemoteNotification: NSObject, Codable {
    public let n_id: String
    public let n_category: String
    public let created_on: TimeInterval
    public let seen_on: TimeInterval?
    public let read_on: TimeInterval?
    public let interacted_on: TimeInterval?
    public let archived: Bool?
    public let tags: [String]?
    public let expiry: TimeInterval?
    public let is_expiry_visible: Bool
    public let is_pinned: Bool
    public let can_user_unpin: Bool?
    public let message: IRemoteNotificationMessage
    
    init(
        n_id: String,
        n_category: String,
        created_on: TimeInterval,
        seen_on: TimeInterval?,
        read_on: TimeInterval? = nil,
        interacted_on: TimeInterval?,
        archived: Bool?,
        tags: [String]?,
        expiry: TimeInterval?,
        is_expiry_visible: Bool,
        is_pinned: Bool,
        can_user_unpin: Bool?,
        message: IRemoteNotificationMessage
    ) {
        self.n_id = n_id
        self.n_category = n_category
        self.created_on = created_on
        self.seen_on = seen_on
        self.read_on = read_on
        self.interacted_on = interacted_on
        self.archived = archived
        self.tags = tags
        self.expiry = expiry
        self.is_expiry_visible = is_expiry_visible
        self.is_pinned = is_pinned
        self.can_user_unpin = can_user_unpin
        self.message = message
    }
    
    func with(seen_on: TimeInterval) -> IRemoteNotification {
        .init(
            n_id: n_id,
            n_category: n_category,
            created_on: created_on,
            seen_on: seen_on,
            read_on: read_on,
            interacted_on: interacted_on,
            archived: archived,
            tags: tags,
            expiry: expiry,
            is_expiry_visible: is_expiry_visible,
            is_pinned: is_pinned,
            can_user_unpin: can_user_unpin,
            message: message
        )
    }
    
    func with(read_on: TimeInterval?) -> IRemoteNotification {
        .init(
            n_id: n_id,
            n_category: n_category,
            created_on: created_on,
            seen_on: seen_on,
            read_on: read_on,
            interacted_on: interacted_on,
            archived: archived,
            tags: tags,
            expiry: expiry,
            is_expiry_visible: is_expiry_visible,
            is_pinned: is_pinned,
            can_user_unpin: can_user_unpin,
            message: message
        )
    }
    
    func with(interacted_on: TimeInterval) -> IRemoteNotification {
        .init(
            n_id: n_id,
            n_category: n_category,
            created_on: created_on,
            seen_on: seen_on,
            read_on: read_on,
            interacted_on: interacted_on,
            archived: archived,
            tags: tags,
            expiry: expiry,
            is_expiry_visible: is_expiry_visible,
            is_pinned: is_pinned,
            can_user_unpin: can_user_unpin,
            message: message
        )
    }
}

public class IPageInfo: NSObject, Codable {
    public let total: UInt
    public let hasMore: Bool
    public let pageSize: UInt
    
    init(total: UInt, hasMore: Bool, pageSize: UInt) {
        self.total = total
        self.hasMore = hasMore
        self.pageSize = pageSize
    }
}

public enum APIResponseStatus: String, Codable {
    case initial = "INITIAL" //  Before any request is made (or after a reset).
    case loading = "LOADING" // The initial API call is in progress
    case success = "SUCCESS" // The API call was successful, and data has been received
    case error = "ERROR" // The API call failed (network issue, server issue, etc.)
    case fetchingMore = "FETCHING_MORE" //  The API call is fetching additional data (for pagination or infinite scroll)
}

public class IInboxFetchOptions: NSObject {
    public let pageSize: UInt?
    
    init(pageSize: UInt?) {
        self.pageSize = pageSize
    }
}
