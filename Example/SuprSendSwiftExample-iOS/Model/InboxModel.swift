//
//  InboxModel.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 31/07/25.
//

import Foundation
import SuprSend
import Combine

struct Action {
    let id = UUID()
    let name: String
    let url: URL?
    let useBrowser: Bool
    
    static func with(_ action: IActionObject) -> Action {
        Action(
            name: action.name,
            url: URL(string: action.url),
            useBrowser: action.open_in_new_tab ?? false
        )
    }
}

struct Message {
    let id: String
    let header: String
    let text: String
    let isRead: Bool
    let time: String
    let url: URL?
    let useBrowser: Bool
    let actions: [Action]
    
    static func with(_ notification: IRemoteNotification) -> Message {
        Message(
            id: notification.n_id,
            header: notification.message.header ?? "",
            text: notification.message.text,
            isRead: notification.read_on != nil,
            time: Date(timeIntervalSince1970: notification.created_on).formatDate(format: "d MMM"),
            url: URL(string: notification.message.url ?? ""),
            useBrowser: notification.message.open_in_new_tab ?? false,
            actions: notification.message.actions?.map(Action.with) ?? []
        )
    }
}

class InboxViewModel: ObservableObject {
    @Published var isLoading: Bool
    private var feedData: FeedData? {
        didSet {
            messages = feedData?.results?.map(Message.with) ?? []
        }
    }
    @Published var messages: [Message] = []
    private var feed: Feed
    
    init() {
        
        let feedOptions = IFeedOptions(
            tenantId: nil,
            pageSize: nil,
            stores: nil,
            host: FeedHost(
                socketHost: SuprSendConstants.socketHost,
                apiHost: SuprSendConstants.inboxHost
            )
        )
        feed = SuprSend.shared.feeds.initialize(options: feedOptions)
        
        isLoading = true
        fetchAll()
    }
    
    deinit {
        SuprSend.shared.feeds.removeInstance(feed)
    }
    
    func markAllAsRead() {
        Task {
            await feed.markAllAsRead()
        }
    }
    
    func markAsRead(item: Message) {
        Task {
            await feed.markAsRead(notificationId: item.id)
        }
    }
    
    func markAsUnread(item: Message) {
        Task {
            await feed.markAsUnread(notificationId: item.id)
        }
    }
    
    func archive(item: Message) {
        Task {
            await feed.markAsArchived(notificationId: item.id)
        }
    }
}

extension InboxViewModel {
    
    func fetchAll() {
        isLoading = true
        Task {
            let result = await feed.fetch()
            DispatchQueue.main.async {
                self.feedData = result.body
                self.isLoading = false
            }
        }
    }
}
