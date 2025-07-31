//
//  Test.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/07/25.
//

import Testing
@testable import SuprSend

class FeedTest {
    let client: SuprSendClient
    let feed: Feed
    
    init() async {
        let publicKey = ""
        let host = ""
        let distinctID = ""
        let socketHost = ""
        let inboxHost = ""
        
        self.client = SuprSend.shared
        
        client.configure(
            publicKey: publicKey,
            options: .init(host: host)
        )
        
        client.enableLogging()
        
        let response = await client.identify(
            distinctID: distinctID
        )
        
        #expect(response.error?.type == nil)
        #expect(response.error?.message == nil)
        
        let feedOptions = IFeedOptions(
            tenantId: nil,
            pageSize: nil,
            stores: nil,
            host: FeedHost(
                socketHost: socketHost,
                apiHost: inboxHost
            )
        )
        
        self.feed = client.feeds.initialize(options: feedOptions)
    }
    
    deinit {
        client.feeds.removeAll()
    }
    
    @Test func fetchCount() async throws {
        let responseCount = await feed.fetchCount()
        
        #expect(responseCount.error?.type == nil)
        #expect(responseCount.error?.message == nil)
        #expect(responseCount.body?.badge != nil)
    }
    
    @Test func fetch() async throws {
        let responseCount = await feed.fetch()
        
        #expect(responseCount.error?.type == nil)
        #expect(responseCount.error?.message == nil)
        #expect(responseCount.body?.results != nil)
        #expect(responseCount.body?.meta != nil)
    }

}
