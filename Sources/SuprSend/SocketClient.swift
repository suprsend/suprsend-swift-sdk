import Foundation
import Network
import Combine

class SocketClient: NSObject, ObservableObject {
    
    struct SocketMessage: Decodable {
        let event: EventType
        let data: [String: AnyDecodable]?
        
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

                // Frames may carry trailing metadata after the payload; the payload is index 1.
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
    
    private(set) var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var heartbeatTask: Task<Void, Never>?
    private var reconnectionTask: Task<Void, Never>?

    var isReconnecting: Bool { reconnectionTask != nil }

    // Engine.IO v4 is server-driven: server sends "2", client replies "3".
    private var serverPingInterval: TimeInterval = 25.0
    private var serverPingTimeout: TimeInterval = 20.0
    private let heartbeatCheckInterval: UInt64 = 5_000_000_000

    private let reconnectionDelay: TimeInterval = 1.0
    private let reconnectionDelayMax: TimeInterval = 10.0

    private var lastPongReceived = Date()
    private var reconnectionAttempts = 0
    private let maxReconnectionAttempts = 25
    
    // Mirrors socket.io-client `socket.active`: false once the client or server ends the session.
    private(set) var active = false

    private var serverURL: String
    private(set) var headers: [String: String]
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    let receivedMessage: PassthroughSubject<SocketMessage, Never> = .init()
    let connectionLost: PassthroughSubject<Void, Never> = .init()
    let connectError: PassthroughSubject<String, Never> = .init()
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
    
    func connect() {
        guard let url = socketIOURL(from: serverURL) else {
            logger.error("Invalid URL: \(serverURL)")
            return
        }

        guard connectionStatus != .connected && connectionStatus != .connecting else {
            logger.info("Already connected or connecting")
            return
        }

        active = true
        connectionStatus = .connecting

        let request = URLRequest(url: url)

        // Cancel the previous task first or its room stays joined and events duplicate.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        listen()
    }

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
    
    func updateHeaders(_ headers: [String: String]) {
        self.headers = headers
    }

    func disconnect() {
        active = false
        logger.info("Disconnecting socket")
        stopKeepAlive()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        // URLSession retains its delegate until invalidated; without this the client is never freed.
        urlSession?.invalidateAndCancel()
        urlSession = nil
        connectionStatus = .disconnected
        reconnectionAttempts = 0
    }
    
    private func startKeepAlive() {
        lastPongReceived = Date()

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
    
    func sendMessage(_ text: String) {
        // Not gated on .connected: the "40" connect frame and pongs go out before the server accepts.
        guard webSocketTask != nil else {
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
    
    private func listen() {
        // Ignore callbacks from a task we've already replaced.
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

                self.listen()

            case .failure(let error):
                self.connectionStatus = .error
                self.error = "Receive failed: \(error.localizedDescription)"
                logger.error("Receive failed: \(error.localizedDescription)")
                if self.active {
                    self.handleConnectionLost()
                }
            }
        }
    }
    
    func handleTextMessage(_ text: String) {
        logger.info("[SuprSendSocket] RX: \(text)")
        // Two-character Socket.IO packets must be matched before the Engine.IO "0"/"2"/"3" checks.
        if text.starts(with: "40") {
            logger.info("Socket.IO namespace connected")
            connectionStatus = .connected
            reconnectionAttempts = 0
        } else if text.starts(with: "41") {
            handleServerRejection(message: "io server disconnect")
        } else if text.starts(with: "44") {
            handleServerRejection(message: connectErrorMessage(from: String(text.dropFirst(2))))
        } else if text.starts(with: "42") {
            let message = text.suffix(from: text.index(text.startIndex, offsetBy: 2))
            parseSocketMessage(jsonString: String(message))
        } else if text.starts(with: "3") {
            lastPongReceived = Date()
        } else if text.starts(with: "0") {
            handleHandshake(jsonString: String(text.dropFirst()))
            sendAuthMessage()
        } else if text.starts(with: "2") {
            lastPongReceived = Date()
            sendMessage("3")
        }
    }

    private func connectErrorMessage(from jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return "connect_error"
        }
        return message
    }

    // Like socket.io-client `destroy()`: a server-ended session is not retried.
    private func handleServerRejection(message: String) {
        logger.error("Socket rejected by server: \(message)")
        active = false
        stopKeepAlive()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .error
        error = message
        connectError.send(message)
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
        let threshold = serverPingInterval + serverPingTimeout
        if timeSinceLastPong > threshold {
            logger.warning("Heartbeat timeout - no server frame for \(timeSinceLastPong)s (threshold \(threshold)s)")
            handleConnectionLost()
        }
    }

    private func handleConnectionLost() {
        guard active else { return }
        // Receive-failure and close paths race here; schedule once.
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

        let backoff = reconnectionDelay * pow(2.0, Double(reconnectionAttempts - 1))
        let delay = min(backoff, reconnectionDelayMax)

        logger.warning("Reconnecting in \(delay)s (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")

        // Task.sleep, not Timer: the URLSession delegate queue has no run loop.
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
        // Ignore callbacks from a task we've already replaced.
        guard webSocketTask === self.webSocketTask else {
            logger.info("Ignoring didOpen for stale webSocketTask")
            return
        }

        // Stays .connecting until the server accepts the namespace with "40".
        logger.info("WebSocket connected")
        lastPongReceived = Date()

        startKeepAlive()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.warning("WebSocket closed with code: \(closeCode)")

        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            logger.info("Close reason: \(reasonString)")
        }

        // Ignore callbacks from a task we've already replaced.
        guard webSocketTask === self.webSocketTask else {
            logger.info("Ignoring didClose for stale webSocketTask")
            return
        }

        connectionStatus = .disconnected
        stopKeepAlive()

        // Receive-failure and close paths race here; schedule once.
        if active, reconnectionTask == nil {
            connectionLost.send(())
            scheduleReconnection()
        }
    }
}
