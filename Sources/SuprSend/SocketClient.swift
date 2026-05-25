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

                if parts.count == 2,
                   case .some(.object(let dictionary)) = parts.last {
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
    private var pingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectionTimer: Timer?
    
    private let pingInterval: UInt64 = 25_000_000_000
    private let heartbeatTimeout: UInt64 = 20_000_000_000
    private let reconnectInterval: TimeInterval = 5.0
    
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
        logger.info("🔌 Disconnecting...")
        stopKeepAlive()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .disconnected
        reconnectionAttempts = 0
    }
    
    private func startKeepAlive() {
        lastPongReceived = Date()
        
        // Start ping timer
        pingTask = Task {
            while !Task.isCancelled {
                // Wait 30 seconds
                try? await Task.sleep(nanoseconds: pingInterval)
                
                // Check if still should continue
                guard !Task.isCancelled else { break }
                
                // Send heartbeat on main thread
                await MainActor.run {
                    sendPing()
                }
            }
        }
        
        // Start heartbeat monitor
        heartbeatTask = Task {
            while !Task.isCancelled {
                // Wait 30 seconds
                try? await Task.sleep(nanoseconds: heartbeatTimeout)
                
                // Check if still should continue
                guard !Task.isCancelled else { break }
                
                // Send heartbeat on main thread
                await MainActor.run {
                    checkHeartbeat()
                }
            }
        }
        
        logger.info("Keep-alive started - ping every \(pingInterval)s, timeout after \(heartbeatTimeout)s")
    }
    
    private func stopKeepAlive() {
        pingTask?.cancel()
        heartbeatTask?.cancel()
        reconnectionTimer?.invalidate()
        
        pingTask = nil
        heartbeatTask = nil
        reconnectionTimer = nil
    }
    
    // Send text message
    func sendMessage(_ text: String) {
        guard connectionStatus == .connected else {
            logger.error("❌ Cannot send message - not connected")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.connectionStatus = .error
                self?.error = "Send failed: \(error.localizedDescription)"
                logger.error("❌ Send error: \(error)")
            } else {
                logger.info("✅ Message sent")
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
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
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
            sendAuthMessage()
        } else if text.starts(with: "2") {
            lastPongReceived = Date()
            sendMessage("3")
        } else if text.starts(with: "42") {
            let message = text.suffix(from: text.index(text.startIndex, offsetBy: 2))
            parseSocketMessage(jsonString: String(message))
        }
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
        logger.info("📦 Received data: \(data.count) bytes")
    }
    
    private func checkHeartbeat() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        
        if isTimeIntervalGreater(timeSinceLastPong, than: heartbeatTimeout) {
            logger.warning("💔 Heartbeat timeout - no pong received for \(timeSinceLastPong)s")
            handleConnectionLost()
        }
    }
    
    private func sendPing() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        
        if isTimeIntervalGreater(timeSinceLastPong, than: heartbeatTimeout) {
            sendMessage("2")
        }
    }
    
    private func isTimeIntervalGreater(_ interval: TimeInterval, than nanoseconds: UInt64) -> Bool {
        // Handle edge cases
        guard interval >= 0 else { return false }
        
        // Convert to nanoseconds for comparison
        let intervalAsNanos = interval * 1_000_000_000
        
        // Check for overflow
        if intervalAsNanos > Double(UInt64.max) {
            return true  // TimeInterval is definitely larger
        }
        
        return UInt64(intervalAsNanos) > nanoseconds
    }

    
    private func handleConnectionLost() {
        if connectionStatus == .connected || connectionStatus == .connecting {
            return
        }

        logger.error("🔌 Connection lost - attempting reconnection")
        connectionStatus = .disconnected
        stopKeepAlive()

        connectionLost.send(())
        scheduleReconnection()
    }
    
    private func scheduleReconnection() {
        guard reconnectionAttempts < maxReconnectionAttempts else {
            logger.error("❌ Max reconnection attempts reached")
            return
        }
        
        reconnectionAttempts += 1
        
        // Exponential backoff with max delay
        let delay = min(reconnectInterval * Double(reconnectionAttempts), 30.0)
        
        logger.warning("🔄 Reconnecting in \(delay)s (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}


// MARK: - URLSessionWebSocketDelegate
extension SocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.info("✅ WebSocket connected")
        connectionStatus = .connected
        reconnectionAttempts = 0
        lastPongReceived = Date()
        
        startKeepAlive()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.warning("🔌 WebSocket closed with code: \(closeCode)")
        
        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            logger.info("Close reason: \(reasonString)")
        }
        
        connectionStatus = .disconnected
        stopKeepAlive()

        // Auto-reconnect unless explicitly closed
        if closeCode != .goingAway {
            connectionLost.send(())
            scheduleReconnection()
        }
    }
}
