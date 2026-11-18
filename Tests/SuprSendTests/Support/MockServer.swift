import Foundation

@testable import SuprSend

final class MockURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: String

        static let ok = Stub(statusCode: 200, body: "{}")

        static func json(_ body: String) -> Stub {
            Stub(statusCode: 200, body: body)
        }
    }

    typealias Handler = (URLRequest) -> Stub

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    private static var recorded: [String: [URLRequest]] = [:]
    private static let registration: Void = { URLProtocol.registerClass(MockURLProtocol.self) }()

    // Keyed by host so parallel tests never see each other's traffic.
    static func register(host: String, handler: @escaping Handler) {
        _ = registration
        lock.lock()
        handlers[host] = handler
        recorded[host] = []
        lock.unlock()
    }

    static func requests(host: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded[host] ?? []
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let host = request.url?.host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }

    private static func record(_ request: URLRequest) {
        guard let host = request.url?.host else { return }
        lock.lock()
        recorded[host, default: []].append(request)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        handler(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let request = Self.withBody(request)
        Self.record(request)
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // URLSession hands the body to a URLProtocol as a stream, never as httpBody.
    private static func withBody(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        var copy = request
        copy.httpBody = data
        return copy
    }
}

struct MockBackend {
    static let publicKey = "test-key"

    let host = "mock-\(UUID().uuidString.lowercased()).test"

    var url: String { "https://\(host)" }

    init(handler: @escaping MockURLProtocol.Handler = { _ in .ok }) {
        MockURLProtocol.register(host: host, handler: handler)
    }

    var requests: [URLRequest] {
        MockURLProtocol.requests(host: host)
    }

    var events: [[String: Any]] {
        requests
            .filter { $0.httpMethod == "POST" && $0.path == "/v2/event" }
            .compactMap(\.jsonBody)
            .filter { $0["event"] as? String != "$identify" }
    }

    func client(appInfo: AppInfo? = nil) -> SuprSendClient {
        SuprSendClient(publicKey: Self.publicKey, options: .init(host: url, appInfo: appInfo))
    }

    func identifiedClient(
        distinctID: String = "user-\(UUID().uuidString)",
        tenantId: String? = nil,
        appInfo: AppInfo? = nil
    ) async -> SuprSendClient {
        let client = client(appInfo: appInfo)
        _ = await client.identify(distinctID: distinctID, tenantId: tenantId)
        return client
    }
}

extension URLRequest {
    var path: String {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path } ?? ""
    }

    var percentEncodedQuery: String {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery } ?? ""
    }

    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    var jsonBody: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

func waitUntil(timeoutNanoseconds: UInt64 = 2_000_000_000, _ condition: () -> Bool) async throws {
    let step: UInt64 = 20_000_000
    var waited: UInt64 = 0
    while !condition(), waited < timeoutNanoseconds {
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}
