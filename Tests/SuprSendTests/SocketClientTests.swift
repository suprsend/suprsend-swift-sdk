import Foundation
import Combine
import Testing

@testable import SuprSend

struct SocketClientTests {

    // Unroutable port so the transport never opens; tests drive frames directly.
    private func makeClient() -> SocketClient {
        SocketClient(serverURL: "http://127.0.0.1:1", headers: [:])
    }

    @Test func connectErrorStopsRetrying() {
        let client = makeClient()
        var errors: [String] = []
        let sub = client.connectError.sink { errors.append($0) }
        client.connect()

        client.handleTextMessage(#"44{"message":"limit reached"}"#)

        #expect(client.active == false)
        #expect(client.isReconnecting == false)
        #expect(client.webSocketTask == nil)
        #expect(client.connectionStatus == .error)
        #expect(errors == ["limit reached"])
        sub.cancel()
    }

    @Test func authConnectErrorIsForwarded() {
        let client = makeClient()
        var errors: [String] = []
        let sub = client.connectError.sink { errors.append($0) }
        client.connect()

        client.handleTextMessage(#"44{"message":"Authentication Error: wrong auth token"}"#)

        #expect(errors == ["Authentication Error: wrong auth token"])
        #expect(client.active == false)
        sub.cancel()
    }

    @Test func serverDisconnectStopsRetrying() {
        let client = makeClient()
        client.connect()

        client.handleTextMessage("41")

        #expect(client.active == false)
        #expect(client.isReconnecting == false)
    }

    @Test func goingAwayCloseRetriesWhileActive() throws {
        let client = makeClient()
        client.connect()
        let task = try #require(client.webSocketTask)

        client.urlSession(URLSession.shared, webSocketTask: task, didCloseWith: .goingAway, reason: nil)

        #expect(client.active == true)
        #expect(client.isReconnecting == true)
        client.disconnect()
    }

    @Test func closeAfterDisconnectDoesNotRetry() throws {
        let client = makeClient()
        client.connect()
        let task = try #require(client.webSocketTask)
        client.disconnect()

        client.urlSession(URLSession.shared, webSocketTask: task, didCloseWith: .normalClosure, reason: nil)

        #expect(client.active == false)
        #expect(client.isReconnecting == false)
    }

    @Test func disconnectReleasesClient() async throws {
        weak var weakClient: SocketClient?
        do {
            let client = makeClient()
            weakClient = client
            client.connect()
            client.disconnect()
        }

        // URLSession drops its delegate asynchronously after invalidation.
        for _ in 0..<40 where weakClient != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(weakClient == nil)
    }

    @Test func connectedOnlyAfterNamespaceAck() {
        let client = makeClient()
        client.connect()
        #expect(client.connectionStatus != .connected)

        client.handleTextMessage(#"40{"sid":"abc"}"#)

        #expect(client.connectionStatus == .connected)
        client.disconnect()
    }
}
