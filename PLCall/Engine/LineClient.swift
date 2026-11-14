import Foundation
import Security

/// Checks the server certificate against the configured NAME, whatever host the request used,
/// so the fallback IP address still validates. The chain is still checked against the system roots.
final class PinnedTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let certName: String

    init(certName: String) {
        self.certName = certName
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let policy = SecPolicyCreateSSL(true, certName as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess, SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// The line to the PC. Every request carries the call key; the bridge key never leaves the PC.
actor LineClient {
    enum Failure: Error, Equatable, Sendable {
        case unauthorized, noSession, badAddress, http(Int)

        var message: String {
            switch self {
            case .unauthorized: return "The call key was refused. Load your config again."
            case .noSession: return "No live session. Start Claude Code on the PC first."
            case .badAddress: return "The line address in the config is not a usable address."
            case .http(let code): return "The PC answered with an error (\(code))."
            }
        }
    }

    struct LiveSession: Sendable {
        let id: String
        let title: String?
    }

    private struct Backlog: Decodable {
        let events: [SessionEvent]?
    }

    /// Errors that mean "this address did not answer at all", so the other address is worth a try.
    private static func unreachable(_ code: URLError.Code) -> Bool {
        code == .cannotFindHost || code == .dnsLookupFailed || code == .cannotConnectToHost
    }

    private let key: String
    private let bases: [String]
    private let session: URLSession
    private var baseIndex = 0

    init(config: PLCallConfig) {
        key = config.callKey
        var all = [config.line.base]
        if let address = config.line.fallbackIp, !address.isEmpty, var parts = URLComponents(string: config.line.base) {
            parts.host = address
            if let other = parts.string { all.append(other) }
        }
        bases = all
        let setup = URLSessionConfiguration.ephemeral
        setup.timeoutIntervalForRequest = 20
        setup.waitsForConnectivity = false
        session = URLSession(configuration: setup, delegate: PinnedTrust(certName: config.line.certName), delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    var usingFallback: Bool { baseIndex > 0 }

    /// 204 when the key is good; throws `.unauthorized` on a 401.
    func ping() async throws {
        _ = try await fetch("key")
    }

    func sessions() async throws -> [LiveSession] {
        let data = try await fetch("rc/api/sessions")
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let list = value.array ?? value["sessions"]?.array ?? []   // the bridge sends a bare array or {sessions: [...]}
        return list.compactMap { item -> LiveSession? in
            guard let id = item["id"]?.string else { return nil }
            return LiveSession(id: id, title: item["title"]?.string)
        }
    }

    func events(sid: String, limit: Int) async throws -> [SessionEvent] {
        let data = try await fetch("rc/api/sessions/\(Self.safe(sid))/events?limit=\(limit)")
        return try JSONDecoder().decode(Backlog.self, from: data).events ?? []
    }

    func send(sid: String, text: String, alt: [String] = [], conf: Double? = nil) async throws {
        _ = try await fetch("rc/api/sessions/\(Self.safe(sid))/send", method: "POST", body: BridgeBody.json(BridgeBody.send(text, alt: alt, conf: conf)), timeout: 30)
    }

    /// His words list, rebuilt on the PC from his own notes (GET /vocab), so it can be refreshed without a new build.
    func vocabulary() async throws -> [String] {
        let data = try await fetch("vocab", timeout: 20)
        return (try JSONDecoder().decode(JSONValue.self, from: data))["words"]?.array?.compactMap(\.string) ?? []
    }

    func permission(sid: String, requestID: String, toolUseID: String?, allow: Bool, message: String?) async throws {
        let body = BridgeBody.json(BridgeBody.permission(requestId: requestID, toolUseId: toolUseID, allow: allow, message: message))
        _ = try await fetch("rc/api/sessions/\(Self.safe(sid))/permission", method: "POST", body: body, timeout: 30)
    }

    func dialog(sid: String, requestID: String, toolUseID: String?, question: PermissionRequest.Question, option: Int, input: JSONValue?) async throws {
        guard question.options.indices.contains(option) else { return }
        let body = BridgeBody.json(BridgeBody.dialog(requestId: requestID, toolUseId: toolUseID, question: question, option: option, input: input))
        _ = try await fetch("rc/api/sessions/\(Self.safe(sid))/dialog", method: "POST", body: body, timeout: 30)
    }

    /// The PC's own spoken status ("status") or what is left on the queue ("left"), built from real state, so it answers while the session is busy.
    func status(_ kind: String) async throws -> String {
        let data = try await fetch(kind == "left" ? "left" : "status", timeout: 40)
        guard let text = (try? JSONDecoder().decode(JSONValue.self, from: data))?["text"]?.string, !text.isEmpty else {
            throw PlainError(message: "The PC sent no status.")
        }
        return text
    }

    /// A picture Claude showed on the call, by its path on the line (img/<name>).
    func image(path: String) async throws -> Data {
        guard path.hasPrefix("img/"), !path.contains("..") else { throw PlainError(message: "That is not a picture path.") }
        return try await fetch(path, timeout: 40)
    }

    /// A picture to the PC's private inbox. Returns the file's path on the PC, for Claude to open.
    func upload(jpeg: Data) async throws -> String {
        let data = try await fetch("upload", method: "POST", body: jpeg, timeout: 60)
        guard let path = (try? JSONDecoder().decode(JSONValue.self, from: data))?["path"]?.string, !path.isEmpty else {
            throw PlainError(message: "The PC did not keep the picture.")
        }
        return path
    }


    /// The session's events as they happen. Reconnects by itself with a growing wait, resuming after the last event seen.
    /// It ends by throwing only when the PC refuses (the key, or the session is gone); `onLink` says when the line drops and returns.
    nonisolated func stream(sid: String, fromSeq: Int, onLink: @escaping @Sendable (Bool) -> Void) -> AsyncThrowingStream<SessionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var seq = fromSeq
                var delay = 1.0
                while !Task.isCancelled {
                    var open = false
                    do {
                        try await self.ping()   // also settles which address answers
                        let request = try await self.streamRequest(sid: sid, fromSeq: seq)
                        let (bytes, response) = try await self.session.bytes(for: request)
                        try Self.check(response)
                        open = true
                        delay = 1
                        onLink(true)
                        var parser = SSEParser()
                        var line: [UInt8] = []
                        // Byte by byte: a line reader can drop the blank lines that end each event.
                        for try await byte in bytes {
                            if byte != 0x0A {
                                line.append(byte)
                                continue
                            }
                            let text = String(decoding: line, as: UTF8.self)
                            line.removeAll(keepingCapacity: true)
                            if let message = parser.feed(text), let event = SessionEvent.decode(message.data) {
                                seq = max(seq, event.sequenceNum)
                                continuation.yield(event)
                            }
                        }
                    } catch let failure as Failure {
                        continuation.finish(throwing: failure)
                        return
                    } catch {
                        if Task.isCancelled { break }
                        let idleTimeout = open && (error as? URLError)?.code == .timedOut
                        if !idleTimeout { onLink(false) }   // a quiet session times out and reopens without alarm
                    }
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 2, 15)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamRequest(sid: String, fromSeq: Int) throws -> URLRequest {
        // 120 s without a byte ends the read: a dead connection is noticed within two minutes.
        var request = try makeRequest(bases[baseIndex], "rc/api/sessions/\(Self.safe(sid))/stream?from_seq=\(fromSeq)", method: "GET", body: nil, timeout: 120)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeRequest(_ base: String, _ path: String, method: String, body: Data?, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: base + path) else { throw Failure.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(key, forHTTPHeaderField: "X-Call-Key")
        if let body {
            request.httpBody = body
            request.setValue(body.starts(with: [0xFF, 0xD8, 0xFF]) ? "image/jpeg" : "application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func fetch(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var last: any Error = Failure.badAddress
        for attempt in bases.indices {
            let index = (baseIndex + attempt) % bases.count
            do {
                let request = try makeRequest(bases[index], path, method: method, body: body, timeout: timeout)
                let (data, response) = try await session.data(for: request)
                baseIndex = index
                try Self.check(response)
                return data
            } catch let failure as Failure {
                throw failure
            } catch let error as URLError where Self.unreachable(error.code) {
                last = error
            }
        }
        throw last
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
        if http.statusCode == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
    }

    private static func safe(_ sid: String) -> String {
        sid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sid
    }
}

/// Any error as one plain sentence for the status line.
func plainSentence(_ error: any Error) -> String {
    if let plain = error as? PlainError { return plain.message }
    if let failure = error as? LineClient.Failure { return failure.message }
    if let problem = error as? PLCallConfig.Problem { return problem.description }
    if error is URLError { return "The PC is not answering. Check that Tailscale is on." }
    return "Something went wrong: \(error.localizedDescription)"
}
