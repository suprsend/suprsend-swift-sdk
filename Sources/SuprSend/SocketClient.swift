//
//  SocketClient.swift
//  SuprSend
//
//  Created by Ram Suthar on 31/08/25.
//

import Foundation
import Network
import Combine

/// Socket Connection Manager
class SocketClient: NSObject, ObservableObject {
    
    struct SocketMessage: Decodable {
        let event: EventType
        let data: [String: AnyDecodable]?
        
        /// Server-emitted socket events. `.unknown(String)` captures any event
        /// the SDK doesn't yet model (e.g. `joined_room`) so they don't break
        /// frame decoding; consumers can choose to ignore them. Mirrors the
        /// "silently no-op for unhandled events" behavior of the web SDK's
        /// mitt-based emitter.
        enum EventType: Equatable {
            case notificationUpdate
            case newNotification
            case resetBadge
            case bulkNotificationUpdate
            case unknown(String)

            init(rawValue: String) {
                switch rawValue {
                case "notification_update": self = .notificationUpdate
                case "new_notification": self = .newNotification
                case "reset_badge": self = .resetBadge
                case "bulk_notification_update": self = .bulkNotificationUpdate
                default: self = .unknown(rawValue)
                }
            }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let parts = try container.decode([AnyDecodable].self)

            guard !parts.isEmpty else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty Data")
            }

            if case .some(.string(let string)) = parts.first,
                !string.isEmpty {
                self.event = EventType(rawValue: string)

                // socket.io frames may carry trailing metadata (e.g. a Redis
                // stream ID) after the payload, so accept any frame with >=2
                // elements and read the payload at index 1.
                if parts.count >= 2,
                   case .object(let dictionary) = parts[1] {
                    self.data = dictionary
                } else {
                    self.data = nil
                }
            } else {
                throw DecodingError
                    .dataCorruptedError(in: container, debugDescription: "No Event Type")
            }
        }
    }
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Keep-alive configuration
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectionTask: Task<Void, Never>?

    // Engine.IO v4 is server-driven: the server sends "2" pings, the client
    // replies "3". The interval/timeout come from the `0{...}` handshake frame
    // (see `handleHandshake`); these are the engine.io defaults used until the
    // real values arrive. Matches suprsend-web-sdk, which delegates heartbeat
    // to socket.io-client.
    private var serverPingInterval: TimeInterval = 25.0
    private var serverPingTimeout: TimeInterval = 20.0
    private let heartbeatCheckInterval: UInt64 = 5_000_000_000

    // Reconnect backoff matches suprsend-web-sdk (socket.io-client defaults).
    private let reconnectionDelay: TimeInterval = 1.0
    private let reconnectionDelayMax: TimeInterval = 10.0

    // Connection state
    private var lastPongReceived = Date()
    private var reconnectionAttempts = 0
    private let maxReconnectionAttempts = 25
    
    private var userInitiatedDisconnect: Bool = false
    
    private var serverURL: String
    private var headers: [String: String]
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    let receivedMessage: PassthroughSubject<SocketMessage, Never> = .init()
    /// Fires whenever a connection is lost or closed unexpectedly, before a
    /// reconnect is scheduled. Lets Feed refresh auth headers if the cause was
    /// JWT expiry, so the upcoming reconnect uses a fresh token.
    let connectionLost: PassthroughSubject<Void, Never> = .init()
    @Published var error: String?
    
    enum ConnectionStatus {
        case connected
        case disconnected
        case connecting
        case error
    }
    
    init(serverURL: String, headers: [String: String]) {
        self.serverURL = serverURL
        self.headers = headers
        
        super.init()
        
        setupURLSession()
    }
    
    deinit {
        disconnect()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }
    
    // Connect to WebSocket
    func connect() {
        guard let url = socketIOURL(from: serverURL) else {
            logger.error("Invalid URL: \(serverURL)")
            return
        }

        guard connectionStatus != .connected && connectionStatus != .connecting else {
            logger.info("Already connected or connecting")
            return
        }

        userInitiatedDisconnect = false
        connectionStatus = .connecting

        let request = URLRequest(url: url)

        // Tear down any previous task before creating a new one. On heartbeat-
        // timeout-driven reconnects the underlying TCP connection is often
        // still alive on the server, so reassigning `webSocketTask` without
        // cancelling first leaves the old room joined and produces duplicate
        // `joined_room` / `new_notification` events. Stale delegate callbacks
        // from this cancellation are ignored via identity checks below.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start listening for messages
        listen()
    }

    /// Builds the socket.io v4 websocket-transport handshake URL on top of the
    /// configured base host. The Suprsend feed server speaks engine.io/socket.io
    /// v4, so a bare `wss://host/` connection fails the upgrade — we must hit
    /// `/socket.io/?EIO=4&transport=websocket`. Auth is sent over the wire in
    /// the `40` CONNECT packet (see `sendAuthMessage`), not as HTTP headers.
    private func socketIOURL(from base: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/socket.io/"
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name == "EIO" }) {
            query.append(URLQueryItem(name: "EIO", value: "4"))
        }
        if !query.contains(where: { $0.name == "transport" }) {
            query.append(URLQueryItem(name: "transport", value: "websocket"))
        }
        components.queryItems = query
        return components.url
    }
    
    /// Replaces the auth headers used on subsequent reconnect attempts.
    /// Caller should typically invoke this in response to `connectionLost`
    /// after refreshing an expired user token.
    func updateHeaders(_ headers: [String: String]) {
        self.headers = headers
    }

    // Disconnect from WebSocket
    func disconnect() {
        userInitiatedDisconnect = true
        logger.info("Disconnecting socket")
        stopKeepAlive()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .disconnected
        reconnectionAttempts = 0
    }
    
    private func startKeepAlive() {
        lastPongReceived = Date()

        // Engine.IO v4 is server-driven, so this is only a dead-connection
        // watchdog: every `heartbeatCheckInterval` we verify that a server
        // ping (or any traffic) has arrived within
        // `serverPingInterval + serverPingTimeout`. No client-initiated pings.
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: heartbeatCheckInterval)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    checkHeartbeat()
                }
            }
        }

        logger.info("Keep-alive started - pingInterval=\(serverPingInterval)s pingTimeout=\(serverPingTimeout)s")
    }

    private func stopKeepAlive() {
        heartbeatTask?.cancel()
        reconnectionTask?.cancel()

        heartbeatTask = nil
        reconnectionTask = nil
    }
    
    // Send text message
    func sendMessage(_ text: String) {
        guard connectionStatus == .connected else {
            logger.error("Cannot send message - not connected")
            return
        }

        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.connectionStatus = .error
                self?.error = "Send failed: \(error.localizedDescription)"
                logger.error("Send error: \(error)")
            } else {
                logger.info("Message sent")
            }
        }
    }
    
    // Send data message
    func sendData(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.connectionStatus = .error
                self?.error = "Send failed: \(error.localizedDescription)"
                logger.error("WebSocket send error: \(error)")
            }
        }
    }
    
    // Listen for incoming messages
    private func listen() {
        // Capture the task we're listening on so we can detect (and ignore)
        // callbacks for a task we've already replaced — otherwise the in-flight
        // receive on the previous task, completing with an error after we
        // cancel it in `connect()`, would trigger `handleConnectionLost` and
        // clobber the new socket's status / keep-alive state.
        let task = webSocketTask
        task?.receive { [weak self] result in
            guard let self else { return }
            guard task === self.webSocketTask else {
                logger.info("Ignoring receive callback for stale webSocketTask")
                return
            }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleTextMessage(text)
                case .data(let data):
                    self.handleDataMessage(data)
                @unknown default:
                    break
                }

                // Continue listening
                self.listen()

            case .failure(let error):
                self.connectionStatus = .error
                self.error = "Receive failed: \(error.localizedDescription)"
                logger.error("Receive failed: \(error.localizedDescription)")
                if !self.userInitiatedDisconnect {
                    self.handleConnectionLost()
                }
            }
        }
    }
    
    
    private func handleTextMessage(_ text: String) {
        logger.info("[SuprSendSocket] RX: \(text)")
        if text.starts(with: "3"){
            lastPongReceived = Date()
        } else if text.starts(with: "0") {
            // engine.io handshake — `0{"sid":...,"pingInterval":25000,"pingTimeout":20000}`.
            // The web-sdk lets socket.io-client read these and so do we; treat
            // anything we can't parse as the engine.io defaults already in place.
            handleHandshake(jsonString: String(text.dropFirst()))
            sendAuthMessage()
        } else if text.starts(with: "2") {
            lastPongReceived = Date()
            sendMessage("3")
        } else if text.starts(with: "42") {
            let message = text.suffix(from: text.index(text.startIndex, offsetBy: 2))
            parseSocketMessage(jsonString: String(message))
        }
    }

    private func handleHandshake(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let pi = json["pingInterval"] as? Double {
            serverPingInterval = pi / 1000.0
        }
        if let pt = json["pingTimeout"] as? Double {
            serverPingTimeout = pt / 1000.0
        }
        logger.info("Engine.IO handshake: pingInterval=\(serverPingInterval)s pingTimeout=\(serverPingTimeout)s")
    }
    
    private func parseSocketMessage(jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {
            return
        }
        
        do {
            let message = try JSONDecoder()
                .decode(SocketMessage.self, from: data)
            
            self.receivedMessage.send(message)
        } catch {
            logger.warning("Socket message decoding error: \(error)")
        }
    }
    
    private func sendAuthMessage() {
        do {
            let auth = try JSONEncoder().encode(headers)
            let message = String(data: auth, encoding: .utf8) ?? ""
            sendMessage("40" + message)
        } catch {
            logger.warning("Auth message encoding error: \(error)")
        }
    }
    
    private func handleDataMessage(_ data: Data) {
        logger.info("Received data: \(data.count) bytes")
    }
    
    private func checkHeartbeat() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        // Server pings every `pingInterval` and considers itself unreachable
        // after `pingTimeout` past that; mirroring socket.io-client, we treat
        // the connection as dead once we've gone the full window without any
        // server frame.
        let threshold = serverPingInterval + serverPingTimeout
        if timeSinceLastPong > threshold {
            logger.warning("Heartbeat timeout - no server frame for \(timeSinceLastPong)s (threshold \(threshold)s)")
            handleConnectionLost()
        }
    }


    private func handleConnectionLost() {
        // Bail when the user explicitly disconnected, or when a reconnect is
        // already in flight — prevents double-scheduling when both the receive
        // failure path and the close-delegate path race here.
        if userInitiatedDisconnect { return }
        if reconnectionTask != nil { return }

        logger.error("Connection lost - attempting reconnection")
        connectionStatus = .disconnected
        stopKeepAlive()

        connectionLost.send(())
        scheduleReconnection()
    }

    private func scheduleReconnection() {
        guard reconnectionAttempts < maxReconnectionAttempts else {
            logger.error("Max reconnection attempts reached")
            return
        }

        reconnectionAttempts += 1

        // Exponential backoff capped at `reconnectionDelayMax`. Matches
        // socket.io-client's defaults used by suprsend-web-sdk
        // (`reconnectionDelay: 1000`, `reconnectionDelayMax: 10000`).
        let backoff = reconnectionDelay * pow(2.0, Double(reconnectionAttempts - 1))
        let delay = min(backoff, reconnectionDelayMax)

        logger.warning("Reconnecting in \(delay)s (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")

        // Use Task.sleep rather than Timer.scheduledTimer because this is
        // invoked from the URLSession delegate queue and from `listen()`'s
        // receive completion handler — neither has a guaranteed running run
        // loop, which would silently prevent the Timer from firing.
        reconnectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.reconnectionTask = nil
                self?.connect()
            }
        }
    }
}


// MARK: - URLSessionWebSocketDelegate
extension SocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Ignore callbacks for a task we've already replaced — a stale `open`
        // arriving after we reconnected would otherwise mark the new socket
        // as connected and reset keep-alive state under it.
        guard webSocketTask === self.webSocketTask else {
            logger.info("Ignoring didOpen for stale webSocketTask")
            return
        }

        logger.info("WebSocket connected")
        connectionStatus = .connected
        reconnectionAttempts = 0
        lastPongReceived = Date()

        startKeepAlive()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.warning("WebSocket closed with code: \(closeCode)")

        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            logger.info("Close reason: \(reasonString)")
        }

        // Ignore close callbacks for tasks we've already replaced (typically
        // the previous task we explicitly cancelled in `connect()`).
        guard webSocketTask === self.webSocketTask else {
            logger.info("Ignoring didClose for stale webSocketTask")
            return
        }

        connectionStatus = .disconnected
        stopKeepAlive()

        // Auto-reconnect unless explicitly closed. Guard against double-
        // scheduling when both this path and `listen()`'s receive-failure path
        // race here for the same disconnect.
        if closeCode != .goingAway, reconnectionTask == nil {
            connectionLost.send(())
            scheduleReconnection()
        }
    }
}
