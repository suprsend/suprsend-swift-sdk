import Foundation

final class MockURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: String
    }

    typealias Handler = (URLRequest) -> Stub

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    private static var recorded: [String: [URLRequest]] = [:]
    private static let registration: Void = { URLProtocol.registerClass(MockURLProtocol.self) }()

    // Keyed by host so suites using the real network or other hosts are never intercepted.
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
}
