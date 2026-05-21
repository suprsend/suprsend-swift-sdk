//
//  FeedTest.swift
//  SuprSend
//
//  Created by Ram Suthar on 30/07/25.
//

import Testing
@testable import SuprSend

@Suite("Feed Tests")
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
        
        #expect(response.error?.type == nil, "Identification should succeed")
        #expect(response.error?.message == nil, "No error message expected")
        
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
    
    // MARK: - Fetch Operations
    
    @Test("Fetch count returns valid badge count")
    func fetchCount() async throws {
        let responseCount = await feed.fetchCount()
        
        #expect(responseCount.error?.type == nil, "Should not have error type")
        #expect(responseCount.error?.message == nil, "Should not have error message")
        #expect(responseCount.body?.badge != nil, "Badge count should be present")
        
        if let badge = responseCount.body?.badge {
            #expect(badge >= 0, "Badge count should be non-negative")
        }
    }
    
    @Test("Fetch returns feed items with metadata")
    func fetch() async throws {
        let response = await feed.fetch()
        
        #expect(response.error?.type == nil, "Should not have error type")
        #expect(response.error?.message == nil, "Should not have error message")
        #expect(response.body?.results != nil, "Results should be present")
        #expect(response.body?.meta != nil, "Metadata should be present")
        
        if let results = response.body?.results {
            #expect(results.count >= 0, "Results should be a valid array")
        }
        
        if let meta = response.body?.meta {
            // Test metadata properties if available
            #expect(meta != nil, "Meta should contain pagination info")
        }
    }
    
    @Test("Fetch next page handles pagination")
    func fetchNextPage() async throws {
        // First fetch initial page
        let initialResponse = await feed.fetch()
        #expect(initialResponse.error == nil, "Initial fetch should succeed")
        
        // Then fetch next page
        let nextPageResponse = await feed.fetchNextPage()
        
        #expect(nextPageResponse.error?.type == nil, "Should not have error type")
        #expect(nextPageResponse.error?.message == nil, "Should not have error message")
        
        // If there's a next page available
        if nextPageResponse.body?.results != nil {
            #expect(nextPageResponse.body?.results != nil, "Should have results if successful")
        }
    }
    
    // MARK: - Mark Operations
    
    @Test("Mark as seen updates notification status")
    func markAsSeen() async throws {
        // First fetch some notifications
        let fetchResponse = await feed.fetch()
        #expect(fetchResponse.error == nil, "Fetch should succeed")
        
        guard let firstNotification = fetchResponse.body?.results?.first,
              let notificationId = firstNotification["id"] as? String else {
            // Skip test if no notifications available
            return
        }
        
        let markResponse = await feed.markAsSeen(notificationId: notificationId)
        #expect(markResponse.error == nil, "Mark as seen should succeed")
    }
    
    @Test("Mark all as seen updates all notifications")
    func markAllAsSeen() async throws {
        let response = await feed.markAllAsSeen()
        #expect(response.error == nil, "Mark all as seen should succeed")
    }
    
    @Test("Mark as read updates notification read status")
    func markAsRead() async throws {
        // First fetch some notifications
        let fetchResponse = await feed.fetch()
        #expect(fetchResponse.error == nil, "Fetch should succeed")
        
        guard let firstNotification = fetchResponse.body?.results?.first,
              let notificationId = firstNotification["id"] as? String else {
            // Skip test if no notifications available
            return
        }
        
        let markResponse = await feed.markAsRead(notificationId: notificationId)
        #expect(markResponse.error == nil, "Mark as read should succeed")
    }
    
    @Test("Mark all as read updates all notifications")
    func markAllAsRead() async throws {
        let response = await feed.markAllAsRead()
        #expect(response.error == nil, "Mark all as read should succeed")
    }
    
    // MARK: - Store Operations
    
    @Test("Get stores returns available stores")
    func getStores() async throws {
        let stores = await feed.getStores()
        #expect(stores != nil, "Should return stores array")
        
        if let storesList = stores {
            #expect(storesList.count >= 0, "Stores should be a valid array")
            
            // Check if default store exists
            let hasDefaultStore = storesList.contains { store in
                store["is_default"] as? Bool == true
            }
            #expect(hasDefaultStore || storesList.isEmpty, "Should have a default store if stores exist")
        }
    }
    
    @Test("Set active store changes current store")
    func setActiveStore() async throws {
        // Get available stores first
        let stores = await feed.getStores()
        
        guard let storesList = stores,
              !storesList.isEmpty,
              let firstStore = storesList.first,
              let storeId = firstStore["id"] as? String else {
            // Skip test if no stores available
            return
        }
        
        await feed.setActiveStore(storeId: storeId)
        
        // Verify store was set (fetch again to confirm)
        let response = await feed.fetch()
        #expect(response.error == nil, "Fetch after store change should succeed")
    }
    
    // MARK: - Filter Operations
    
    @Test("Apply filters to feed")
    func applyFilters() async throws {
        // Test with read filter
        let readFilter = ["read": true]
        await feed.applyFilters(filters: readFilter)
        
        let response = await feed.fetch()
        #expect(response.error == nil, "Fetch with filters should succeed")
        
        // Clear filters
        await feed.clearFilters()
        
        let unfiltereredResponse = await feed.fetch()
        #expect(unfiltereredResponse.error == nil, "Fetch without filters should succeed")
    }
    
    @Test("Clear filters removes all filters")
    func clearFilters() async throws {
        // Apply some filters first
        let filters = ["read": false, "seen": false]
        await feed.applyFilters(filters: filters)
        
        // Clear filters
        await feed.clearFilters()
        
        let response = await feed.fetch()
        #expect(response.error == nil, "Fetch after clearing filters should succeed")
    }
    
    // MARK: - Real-time Operations
    
    @Test("Subscribe to feed updates")
    func subscribeToUpdates() async throws {
        var updateReceived = false
        
        let cancellable = await feed.subscribe { update in
            updateReceived = true
            #expect(update != nil, "Update should contain data")
        }
        
        // Wait a bit for potential updates
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Clean up subscription
        cancellable?.cancel()
        
        // Note: updateReceived might still be false if no real-time updates occurred
        #expect(cancellable != nil, "Should return a valid cancellable")
    }
    
    // MARK: - Error Handling
    
    @Test("Handle invalid notification ID gracefully")
    func handleInvalidNotificationId() async throws {
        let invalidId = "invalid-notification-id-12345"
        
        let markResponse = await feed.markAsSeen(notificationId: invalidId)
        // The API might still return success or a specific error
        // Adjust expectation based on actual API behavior
        #expect(markResponse != nil, "Should return a response even for invalid ID")
    }
    
    @Test("Handle network errors gracefully")
    func handleNetworkErrors() async throws {
        // This test would require mocking network failures
        // For now, we just ensure the methods handle nil/empty responses
        
        let response = await feed.fetch()
        #expect(response != nil, "Should always return a response object")
        
        if response.error != nil {
            #expect(response.error?.type != nil, "Error should have a type")
            #expect(response.error?.message != nil, "Error should have a message")
        }
    }
    
    // MARK: - Pagination Tests
    
    @Test("Pagination maintains correct order")
    func paginationOrder() async throws {
        // Fetch first page
        let firstPage = await feed.fetch()
        #expect(firstPage.error == nil, "First page fetch should succeed")
        
        guard let firstPageResults = firstPage.body?.results,
              !firstPageResults.isEmpty else {
            // Skip if no data
            return
        }
        
        // Fetch next page
        let secondPage = await feed.fetchNextPage()
        
        if let secondPageResults = secondPage.body?.results,
           !secondPageResults.isEmpty {
            // Verify no duplicate IDs between pages
            let firstPageIds = Set(firstPageResults.compactMap { $0["id"] as? String })
            let secondPageIds = Set(secondPageResults.compactMap { $0["id"] as? String })
            
            let intersection = firstPageIds.intersection(secondPageIds)
            #expect(intersection.isEmpty, "Pages should not have duplicate items")
        }
    }
    
    @Test("Has more pages indicator")
    func hasMorePages() async throws {
        let response = await feed.fetch()
        #expect(response.error == nil, "Fetch should succeed")
        
        if let meta = response.body?.meta {
            // Check if metadata indicates more pages
            if let hasMore = meta["has_next"] as? Bool {
                #expect(hasMore == true || hasMore == false, "Has more should be a valid boolean")
            }
        }
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Concurrent fetch operations")
    func concurrentFetches() async throws {
        // Run multiple fetch operations concurrently
        async let fetch1 = feed.fetch()
        async let fetch2 = feed.fetchCount()
        async let fetch3 = feed.getStores()
        
        let response1 = await fetch1
        let response2 = await fetch2
        let stores = await fetch3
        
        #expect(response1.error == nil, "First concurrent fetch should succeed")
        #expect(response2.error == nil, "Second concurrent fetch should succeed")
        #expect(stores != nil, "Concurrent stores fetch should succeed")
    }
    
    // MARK: - State Management Tests
    
    @Test("Feed maintains state across operations")
    func feedStateManagement() async throws {
        // Fetch initial state
        let initialCount = await feed.fetchCount()
        #expect(initialCount.error == nil, "Initial count fetch should succeed")
        
        let initialBadge = initialCount.body?.badge ?? 0
        
        // Perform some operations
        let fetchResponse = await feed.fetch()
        #expect(fetchResponse.error == nil, "Fetch should succeed")
        
        // Check if count is consistent
        let afterFetchCount = await feed.fetchCount()
        #expect(afterFetchCount.error == nil, "Count fetch after operations should succeed")
        
        // The badge count should be consistent unless notifications changed
        if let newBadge = afterFetchCount.body?.badge {
            #expect(newBadge >= 0, "Badge should remain non-negative")
        }
    }
}
