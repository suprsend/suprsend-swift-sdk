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
        
        enum EventType: String, Codable {
            case notificationUpdate = "notification_update"
            case newNotification = "new_notification"
            case resetBadge = "reset_badge"
            case bulkNotificationUpdate = "bulk_notification_update"
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let parts = try container.decode([AnyDecodable].self)
            
            guard !parts.isEmpty else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty Data")
            }
            
            if case .some(.string(let string)) = parts.first,
                !string.isEmpty {
                guard let event = EventType(rawValue: string) else {
                    throw DecodingError
                        .dataCorruptedError(in: container, debugDescription: "Unknown Event Type: \(string)")
                }
                
                self.event = event
                
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
        guard let url = URL(string: serverURL) else {
            logger.error("Invalid URL: \(serverURL)")
            return
        }
        
        guard connectionStatus != .connected && connectionStatus != .connecting else {
            logger.info("Already connected or connecting")
            return
        }
        
        userInitiatedDisconnect = false
        connectionStatus = .connecting
        
        var request = URLRequest(url: url)
        
        // Add auth headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages
        listen()
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
        // Handle pong or other keep-alive messages
        if text.starts(with: "3"){
            lastPongReceived = Date()
            logger.info("🏓 Pong received")
        } else if text.starts(with: "0") {
            sendAuthMessage()
        } else if text.starts(with: "2") {
            lastPongReceived = Date()
            logger.info("🏓 Ping received")
            sendMessage("3")
        } else if text.starts(with: "42") {
            let message = text.suffix(from: text.index(text.startIndex, offsetBy: 2))
            parseSocketMessage(jsonString: String(message))
            logger.info("📨 Received: \(text)")
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
            scheduleReconnection()
        }
    }
}
