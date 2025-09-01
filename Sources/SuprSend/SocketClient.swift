//
//  SocketClient.swift
//  SuprSend
//
//  Created by Ram Suthar on 31/08/25.
//

import Foundation
import Network

/// Socket Connection Manager
class SocketClient: NSObject, ObservableObject {
    
    struct SocketMessage: Decodable {
        let event: EventType
        let data: [String: AnyDecodable]?
        
        enum EventType: String, Codable {
            case notificationUpdate = "notification_update"
            case newNotification = "new_notification"
            case resetBadge = "reset_badge"
            case bulklNotificationUpdate = "bulk_notification_update"
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let parts = try container.decode([AnyDecodable].self)
            
            if case .some(.string(let string)) = parts.first,
                !string.isEmpty {
                guard let event = EventType(rawValue: string) else {
                    throw DecodingError
                        .dataCorruptedError(in: container, debugDescription: "Unknown Event Type: \(string)")
                }
                
                self.event = event
                
                if case .some(.object(let dictionary)) = parts.last {
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
    private var pingTimer: Timer?
    private var heartbeatTimer: Timer?
    private var reconnectionTimer: Timer?
    
    private let pingInterval: TimeInterval = 5.0
    private let heartbeatTimeout: TimeInterval = 20.0
    private let reconnectInterval: TimeInterval = 5.0
    
    // Connection state
    private var lastPongReceived = Date()
    private var reconnectionAttempts = 0
    private let maxReconnectionAttempts = 25
    
    private var serverURL: String
    private var headers: [String: String]
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var receivedMessages: [SocketMessage] = []
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
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }
    
    // Connect to WebSocket
    func connect() {
        guard let url = URL(string: serverURL) else {
            print("Invalid URL: \(serverURL)")
            return
        }
        
        guard connectionStatus != .connected && connectionStatus != .connecting else {
            print("Already connected or connecting")
            return
        }
        
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
        
        // Monitor connection status
        monitorConnection()
    }
    
    // Disconnect from WebSocket
    func disconnect() {
        print("🔌 Disconnecting...")
        stopKeepAlive()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .disconnected
    }
    
    private func startKeepAlive() {
        lastPongReceived = Date()
        
        // Start ping timer
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        
        // Start heartbeat monitor
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatTimeout, repeats: true) { [weak self] _ in
            self?.checkHeartbeat()
        }
        
        print("Keep-alive started - ping every \(pingInterval)s, timeout after \(heartbeatTimeout)s")
    }
    
    private func stopKeepAlive() {
        pingTimer?.invalidate()
        heartbeatTimer?.invalidate()
        reconnectionTimer?.invalidate()
        
        pingTimer = nil
        heartbeatTimer = nil
        reconnectionTimer = nil
    }
    
    // Send text message
    func sendMessage(_ message: String) {
        guard connectionStatus == .connected else {
            print("❌ Cannot send message - not connected")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(message) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.connectionStatus = .error
                    self?.error = "Send failed: \(error.localizedDescription)"
                    print("❌ Send error: \(error)")
                } else {
                    print("✅ Message sent: \(message)")
                }
            }
        }
    }
    
    // Send data message
    func sendData(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.connectionStatus = .error
                    self?.error = "Send failed: \(error.localizedDescription)"
                    print("WebSocket send error: \(error)")
                }
            }
        }
    }
    
    // Listen for incoming messages
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleTextMessage(text)
                case .data(let data):
                    self?.handleDataMessage(data)
                @unknown default:
                    break
                }
                
                // Continue listening
                self?.listen()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.connectionStatus = .error
                    self?.error = "Receive failed: \(error.localizedDescription)"
                }
                self?.handleConnectionLost()
            }
        }
    }
    
    
    private func handleTextMessage(_ text: String) {
        print("📨 Received: \(text)")
        
        // Handle pong or other keep-alive messages
        if text.lowercased().contains("pong"){
            lastPongReceived = Date()
            print("🏓 Pong received")
        } else if text.starts(with: "0") {
            sendAuthMessage()
        } else if text.starts(with: "2") {
            print("🏓 Ping received")
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
            
            DispatchQueue.main.async {
                self.receivedMessages.append(message)
            }
        } catch {
            debugPrint("Socket message decoding error: \(error)")
        }
    }
    
    private func sendAuthMessage() {
        do {
            let auth = try JSONEncoder().encode(headers)
            let message = String(data: auth, encoding: .utf8) ?? ""
            sendMessage("40" + message)
        } catch {
            debugPrint("Auth message encoding error: \(error)")
        }
    }
    
    private func handleDataMessage(_ data: Data) {
        print("📦 Received data: \(data.count) bytes")
    }
    
    // Monitor connection status
    private func monitorConnection() {
        // Check if connection is established
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            if self.webSocketTask?.state == .running {
                self.connectionStatus = .connected
            } else if self.webSocketTask?.state == .canceling || self.webSocketTask?.state == .completed {
                self.connectionStatus = .disconnected
            }
        }
    }

    private func sendPing() {
        guard connectionStatus == .connected else { return }
        
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("❌ Ping failed: \(error)")
                self?.connectionStatus = .error
                self?.error = "Ping failed: \(error.localizedDescription)"
                self?.handleConnectionLost()
            } else {
                print("📡 Ping sent")
            }
        }
    }
    
    
    private func checkHeartbeat() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        
        if timeSinceLastPong > heartbeatTimeout {
            print("💔 Heartbeat timeout - no pong received for \(timeSinceLastPong)s")
            handleConnectionLost()
        }
    }
    
    private func handleConnectionLost() {
        guard connectionStatus == .connected else { return }
        
        print("🔌 Connection lost - attempting reconnection")
        connectionStatus = .disconnected
        stopKeepAlive()
        
        scheduleReconnection()
    }
    
    private func scheduleReconnection() {
        guard reconnectionAttempts < maxReconnectionAttempts else {
            print("❌ Max reconnection attempts reached")
            return
        }
        
        reconnectionAttempts += 1
        
        // Exponential backoff with max delay
        let delay = min(reconnectInterval * Double(reconnectionAttempts), 30.0)
        
        print("🔄 Reconnecting in \(delay)s (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}


// MARK: - URLSessionWebSocketDelegate
extension SocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        connectionStatus = .connected
        reconnectionAttempts = 0
        lastPongReceived = Date()
        
        startKeepAlive()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket closed with code: \(closeCode)")
        
        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            print("Close reason: \(reasonString)")
        }
        
        connectionStatus = .disconnected
        stopKeepAlive()
        
        // Auto-reconnect unless explicitly closed
        if closeCode != .goingAway {
            scheduleReconnection()
        }
    }
}
