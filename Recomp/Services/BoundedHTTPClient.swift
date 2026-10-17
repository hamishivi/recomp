import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A one-request transport with a bounded *received* body, including chunked or
/// decompressed responses. No disk cache, cookies, credentials, redirects or retry.
/// Delegate state is lock-protected; completion/cancellation can win only once.
/// Uses the same implementation in iOS and the portable localhost harness.
enum BoundedHTTPClient {
    static func data(for request: URLRequest, maximumBytes: Int = 250_000,
                     requestTimeout: TimeInterval = 90, resourceTimeout: TimeInterval = 100) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes > 0, requestTimeout.isFinite, resourceTimeout.isFinite,
              requestTimeout > 0, resourceTimeout > 0, requestTimeout <= 86_400, resourceTimeout <= 86_400 else { throw EstimateError.invalidResponse }
        let transfer = Transfer(maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                transfer.start(request, requestTimeout: requestTimeout, resourceTimeout: resourceTimeout, continuation: continuation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }

    private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        typealias Output = (Data, HTTPURLResponse)
        private let lock = NSLock()
        private let maximumBytes: Int
        private var continuation: CheckedContinuation<Output, Error>?
        private var session: URLSession?
        private var response: HTTPURLResponse?
        private var deadline: DispatchSourceTimer?
        private var body = Data()
        private var terminal: Result<Output, Error>?

        init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

        func start(_ request: URLRequest, requestTimeout: TimeInterval, resourceTimeout: TimeInterval,
                   continuation: CheckedContinuation<Output, Error>) {
            lock.lock()
            if let terminal { lock.unlock(); continuation.resume(with: terminal); return }
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = resourceTimeout
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            var request = request
            request.timeoutInterval = requestTimeout
            let task = session.dataTask(with: request)
            // Enforce an overall deadline independently of platform-specific URLSession
            // idle/resource timeout behaviour. Receiving another byte cannot extend it.
            let deadline = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            deadline.schedule(deadline: .now() + resourceTimeout)
            deadline.setEventHandler { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
            self.deadline = deadline
            deadline.resume()
            lock.unlock()
            // If cancellation won after unlocking, the session is invalidated and this
            // resume cannot create a second completion or an uncancellable request.
            task.resume()
        }
        func cancel() { finish(.failure(CancellationError())) }

        private func finish(_ result: Result<Output, Error>) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            terminal = result
            let continuation = self.continuation
            let session = self.session
            let deadline = self.deadline
            self.continuation = nil; self.session = nil; self.deadline = nil; body = Data()
            lock.unlock()
            deadline?.cancel()
            session?.invalidateAndCancel()
            continuation?.resume(with: result)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse,
                  response.expectedContentLength <= Int64(maximumBytes) else {
                finish(.failure(EstimateError.invalidResponse)); completionHandler(.cancel); return
            }
            lock.lock()
            let active = terminal == nil
            if active { self.response = http }
            lock.unlock()
            completionHandler(active ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            let excessive = data.count > maximumBytes - body.count
            if !excessive { body.append(data) }
            lock.unlock()
            if excessive { finish(.failure(EstimateError.invalidResponse)) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let response = self.response, data = body
            lock.unlock()
            if let error { finish(.failure(error)) }
            else if let response { finish(.success((data, response))) }
            else { finish(.failure(EstimateError.invalidResponse)) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            // Never replay the meal or bearer token to an unexpected destination.
            completionHandler(nil)
            finish(.failure(EstimateError.invalidResponse))
        }
    }
}
