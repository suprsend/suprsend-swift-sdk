import Combine
import Foundation
import Testing

@testable import SuprSend

struct FeedTests {

    @Test func fetchLoadsFirstPageWithEncodedQuery() async throws {
        let backend = MockBackend { request in
            Self.feedPath(request) == "notifications" ? .json(Self.pageJSON(["n1", "n2"], page: 1, of: 2)) : .ok
        }
        let distinctID = "john+\(UUID().uuidString)@acme.com"
        let client = await backend.identifiedClient(distinctID: distinctID, tenantId: "tenant-a")
        let feed = Self.makeFeed(client, backend)

        let response = await feed.fetch()

        #expect(response.status == .success)
        #expect(feed.data.apiStatus == .success)
        #expect(feed.data.notifications.map(\.n_id) == ["n1", "n2"])
        #expect(feed.data.pageInfo.hasMore)

        let request = try #require(backend.requests.first { Self.feedPath($0) == "notifications" })
        #expect(request.percentEncodedQuery.contains("distinct_id=john%2B"))
        #expect(request.queryValue("distinct_id") == distinctID)
        #expect(request.queryValue("tenant_id") == "tenant-a")
    }

    @Test func fetchNextPageAppendsUntilLastPage() async {
        let backend = MockBackend { request in
            guard Self.feedPath(request) == "notifications" else { return .ok }
            return request.queryValue("search_after") == "[]"
                ? .json(Self.pageJSON(["n1", "n2"], page: 1, of: 2))
                : .json(Self.pageJSON(["n3"], page: 2, of: 2))
        }
        let client = await backend.identifiedClient()
        let feed = Self.makeFeed(client, backend)

        _ = await feed.fetch()
        let next = await feed.fetchNextPage()
        let afterLast = await feed.fetchNextPage()

        #expect(next.status == .success)
        #expect(feed.data.notifications.map(\.n_id) == ["n1", "n2", "n3"])
        #expect(feed.data.pageInfo.hasMore == false)
        #expect(afterLast.error?.message == "No more pages to fetch")

        let pages = backend.requests.filter { Self.feedPath($0) == "notifications" }
        #expect(pages.count == 2)
        #expect(pages.last?.queryValue("search_after") == "[0,99]")
    }

    @Test func fetchCountUpdatesBadge() async {
        let backend = MockBackend { request in
            Self.feedPath(request) == "notifications_count" ? .json(#"{"badge":3,"unread":2}"#) : .ok
        }
        let client = await backend.identifiedClient()
        let feed = Self.makeFeed(client, backend)

        let response = await feed.fetchCount()

        #expect(response.body?.badge == 3)
        #expect(feed.data.meta["badge"] == "3")
        #expect(feed.data.meta["unread"] == "2")
    }

    @Test func markAsReadUpdatesLocallyAndSendsOnce() async throws {
        let backend = MockBackend { request in
            Self.feedPath(request) == "notifications" ? .json(Self.pageJSON(["n1", "n2"], page: 1, of: 1)) : .ok
        }
        let client = await backend.identifiedClient()
        let feed = Self.makeFeed(client, backend)
        _ = await feed.fetch()

        let first = await feed.markAsRead(notificationId: "n1")
        let repeated = await feed.markAsRead(notificationId: "n1")

        #expect(first.status == .success)
        #expect(repeated.status == .success)
        let read = try #require(feed.data.notifications.first { $0.n_id == "n1" })
        #expect(read.read_on != nil)
        #expect(read.seen_on != nil)
        #expect(feed.data.notifications.first { $0.n_id == "n2" }?.read_on == nil)
        let calls = backend.requests.filter { $0.httpMethod == "PATCH" && Self.feedPath($0) == "notifications/n1/read" }
        #expect(calls.count == 1)
    }

    @Test func markAllAsReadClearsBadgeAndMarksAll() async throws {
        let backend = MockBackend { request in
            switch Self.feedPath(request) {
            case "notifications": return .json(Self.pageJSON(["n1", "n2"], page: 1, of: 1))
            case "notifications_count": return .json(#"{"badge":2}"#)
            default: return .ok
            }
        }
        let client = await backend.identifiedClient()
        let feed = Self.makeFeed(client, backend)
        _ = await feed.fetch()
        // The first fetch loads the badge in a background task; let it land before clearing it.
        try await waitUntil { feed.data.meta["badge"] == "2" }

        let response = await feed.markAllAsRead()

        #expect(response.status == .success)
        #expect(feed.data.meta["badge"] == "0")
        #expect(feed.data.notifications.allSatisfy { $0.read_on != nil })
        #expect(backend.requests.contains { $0.httpMethod == "PATCH" && Self.feedPath($0) == "mark_all_read" })
    }

    @Test func changeActiveStoreValidatesAndRefetches() async throws {
        let backend = MockBackend { request in
            guard Self.feedPath(request) == "notifications" else { return .ok }
            let isUnreadStore = request.queryValue("store")?.contains(#""store_id":"unread""#) == true
            return .json(Self.pageJSON(isUnreadStore ? ["u1"] : ["n1", "n2"], page: 1, of: 1))
        }
        let client = await backend.identifiedClient()
        let stores = [
            IStore(storeId: "all", label: "All"),
            IStore(storeId: "unread", label: "Unread", query: .init(read: false)),
        ]
        let feed = Self.makeFeed(client, backend, stores: stores)
        _ = await feed.fetch()

        let unknown = await feed.changeActiveStore(storeId: "missing")
        #expect(unknown.error?.type == .validation)
        #expect(feed.data.store.storeId == "all")

        let switched = await feed.changeActiveStore(storeId: "unread")
        #expect(switched.status == .success)
        #expect(feed.data.store.storeId == "unread")
        #expect(feed.data.notifications.map(\.n_id) == ["u1"])
    }

    // MARK: - Helpers

    private static func makeFeed(_ client: SuprSendClient, _ backend: MockBackend, stores: [IStore]? = nil) -> Feed {
        client.feeds.initialize(
            options: .init(
                tenantId: nil,
                pageSize: 2,
                stores: stores,
                host: FeedHost(socketHost: nil, apiHost: backend.url)
            )
        )
    }

    private static func feedPath(_ request: URLRequest) -> String? {
        guard let range = request.path.range(of: "/v1/feed/") else { return nil }
        return String(request.path[range.upperBound...])
    }

    private static func pageJSON(_ ids: [String], page: Int, of totalPages: Int) -> String {
        let results = ids.enumerated().map { index, id in
            #"{"n_id":"\#(id)","n_category":"general","created_on":\#(100 - index),"is_expiry_visible":false,"is_pinned":false,"message":{"schema":"1","text":"Hello"}}"#
        }
        return #"{"results":[\#(results.joined(separator: ","))],"meta":{"total_count":3,"current_page":\#(page),"total_pages":\#(totalPages)}}"#
    }
}

struct FeedSocketTests {

    // Unroutable port so the transport never opens; tests drive frames directly.
    private func makeSocket() -> SocketClient {
        SocketClient(serverURL: "http://127.0.0.1:1", headers: [:])
    }

    @Test func connectsOnlyAfterNamespaceAck() {
        let socket = makeSocket()
        socket.connect()
        #expect(socket.connectionStatus != .connected)

        socket.handleTextMessage(#"40{"sid":"abc"}"#)

        #expect(socket.connectionStatus == .connected)
        socket.disconnect()
    }

    @Test func connectErrorStopsRetryingAndIsForwarded() {
        let socket = makeSocket()
        var errors: [String] = []
        let subscription = socket.connectError.sink { errors.append($0) }
        socket.connect()

        socket.handleTextMessage(#"44{"message":"Authentication Error: wrong auth token"}"#)

        #expect(errors == ["Authentication Error: wrong auth token"])
        #expect(socket.active == false)
        #expect(socket.isReconnecting == false)
        #expect(socket.connectionStatus == .error)
        subscription.cancel()
    }

    @Test func retriesUnexpectedCloseButNotServerOrManualDisconnect() throws {
        let dropped = makeSocket()
        dropped.connect()
        let droppedTask = try #require(dropped.webSocketTask)
        dropped.urlSession(URLSession.shared, webSocketTask: droppedTask, didCloseWith: .goingAway, reason: nil)
        #expect(dropped.isReconnecting)
        dropped.disconnect()

        let kicked = makeSocket()
        kicked.connect()
        kicked.handleTextMessage("41")
        #expect(kicked.active == false)
        #expect(kicked.isReconnecting == false)

        let closed = makeSocket()
        closed.connect()
        let closedTask = try #require(closed.webSocketTask)
        closed.disconnect()
        closed.urlSession(URLSession.shared, webSocketTask: closedTask, didCloseWith: .normalClosure, reason: nil)
        #expect(closed.isReconnecting == false)
    }

    @Test func reconnectRecoversWithPidAndOffset() throws {
        let socket = makeSocket()
        var recovered: [Bool] = []
        let subscription = socket.reconnected.sink { recovered.append($0) }
        #expect(!socket.connectPayload().contains("pid"))

        socket.handleTextMessage(#"40{"sid":"a","pid":"p1"}"#)
        socket.handleTextMessage(#"42["new_notification",{"n_id":"1"},"o1"]"#)

        let payload = String(socket.connectPayload().dropFirst(2))
        let auth = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: String])
        #expect(auth["pid"] == "p1")
        #expect(auth["offset"] == "o1")

        socket.handleTextMessage(#"40{"sid":"b","pid":"p1"}"#)
        socket.handleTextMessage(#"40{"sid":"c","pid":"p2"}"#)

        #expect(recovered == [true, false])
        #expect(socket.lastOffset == nil)
        subscription.cancel()
    }
}
