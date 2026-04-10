import Foundation
import Network

enum OpenAIAccountGatewayConfiguration {
    static let host = "127.0.0.1"
    static let port: UInt16 = 1456
    static let apiKey = "codexbar-local-gateway"
    static let upstreamResponsesURL = URL(string: "https://api.openai.com/v1/responses")!

    static var baseURLString: String {
        "http://\(self.host):\(self.port)/v1"
    }
}

private struct OpenAIAccountGatewaySnapshot {
    var accounts: [TokenAccount]
    var quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings
    var accountUsageMode: CodexBarOpenAIAccountUsageMode
    var stickyBindings: [String: String]
}

private struct ParsedGatewayRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

final class OpenAIAccountGatewayService {
    static let shared = OpenAIAccountGatewayService()

    private let listenerQueue = DispatchQueue(label: "lzl.codexbar.openai-gateway.listener")
    private let stateQueue = DispatchQueue(label: "lzl.codexbar.openai-gateway.state")
    private let urlSession: URLSession

    private var listener: NWListener?
    private var accounts: [TokenAccount] = []
    private var quotaSortSettings = CodexBarOpenAISettings.QuotaSortSettings()
    private var accountUsageMode: CodexBarOpenAIAccountUsageMode = .switchAccount
    private var stickyBindings: [String: String] = [:]

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func startIfNeeded() {
        self.listenerQueue.async {
            guard self.listener == nil else { return }

            do {
                let port = NWEndpoint.Port(rawValue: OpenAIAccountGatewayConfiguration.port)!
                let listener = try NWListener(using: .tcp, on: port)
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    connection.start(queue: self.listenerQueue)
                    self.receiveRequest(on: connection, accumulated: Data())
                }
                listener.stateUpdateHandler = { state in
                    if case .failed = state {
                        self.listenerQueue.async {
                            self.listener = nil
                        }
                    }
                }
                self.listener = listener
                listener.start(queue: self.listenerQueue)
            } catch {
                NSLog("codexbar OpenAI gateway failed to start: %@", error.localizedDescription)
            }
        }
    }

    func updateState(
        accounts: [TokenAccount],
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        accountUsageMode: CodexBarOpenAIAccountUsageMode
    ) {
        self.stateQueue.async {
            self.accounts = accounts
            self.quotaSortSettings = quotaSortSettings
            self.accountUsageMode = accountUsageMode
            let knownIDs = Set(accounts.map(\.accountId))
            self.stickyBindings = self.stickyBindings.filter { knownIDs.contains($0.value) }
        }
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("codexbar OpenAI gateway receive failed: %@", error.localizedDescription)
                connection.cancel()
                return
            }

            var combined = accumulated
            if let data {
                combined.append(data)
            }

            if let request = self.parseRequest(from: combined) {
                self.handle(request: request, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            self.receiveRequest(on: connection, accumulated: combined)
        }
    }

    private func parseRequest(from data: Data) -> ParsedGatewayRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else { return nil }

        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyOffset = headerRange.upperBound
        guard data.count >= bodyOffset + contentLength else { return nil }

        let body = data.subdata(in: bodyOffset..<(bodyOffset + contentLength))
        return ParsedGatewayRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }

    private func handle(request: ParsedGatewayRequest, on connection: NWConnection) {
        switch (request.method.uppercased(), request.path) {
        case ("GET", "/v1/responses"):
            // Codex will first probe websocket upgrade on this endpoint. Returning a
            // fast HTTP/1.1 404 forces it onto the HTTP fallback path without waiting
            // for a hung websocket listener.
            self.sendJSONResponse(
                on: connection,
                statusCode: 404,
                body: #"{"error":{"message":"websocket path is not served by codexbar gateway"}}"#
            )
        case ("POST", "/v1/responses"):
            Task {
                await self.forwardResponsesRequest(request, on: connection)
            }
        default:
            self.sendJSONResponse(
                on: connection,
                statusCode: 404,
                body: #"{"error":{"message":"not found"}}"#
            )
        }
    }

    private func snapshot() -> OpenAIAccountGatewaySnapshot {
        self.stateQueue.sync {
            OpenAIAccountGatewaySnapshot(
                accounts: self.accounts,
                quotaSortSettings: self.quotaSortSettings,
                accountUsageMode: self.accountUsageMode,
                stickyBindings: self.stickyBindings
            )
        }
    }

    private func stickySessionKey(for headers: [String: String]) -> String? {
        let candidates = [
            headers["session_id"],
            headers["x-client-request-id"],
            headers["x-codex-window-id"],
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false })
    }

    private func candidates(for snapshot: OpenAIAccountGatewaySnapshot, stickyKey: String?) -> [TokenAccount] {
        guard snapshot.accountUsageMode == .aggregateGateway else { return [] }

        let usable = snapshot.accounts.filter {
            $0.isAvailableForNextUseRouting
        }
        var ordered = usable.sorted {
            OpenAIAccountListLayout.accountPrecedes(
                $0,
                $1,
                quotaSortSettings: snapshot.quotaSortSettings
            )
        }

        if let stickyKey,
           let stickyAccountID = snapshot.stickyBindings[stickyKey],
           let index = ordered.firstIndex(where: { $0.accountId == stickyAccountID }) {
            let stickyAccount = ordered.remove(at: index)
            ordered.insert(stickyAccount, at: 0)
        }

        return ordered
    }

    private func bind(stickyKey: String?, accountID: String) {
        guard let stickyKey, stickyKey.isEmpty == false else { return }
        self.stateQueue.async {
            self.stickyBindings[stickyKey] = accountID
        }
    }

    private func clearBinding(stickyKey: String?, accountID: String) {
        guard let stickyKey, stickyKey.isEmpty == false else { return }
        self.stateQueue.async {
            guard self.stickyBindings[stickyKey] == accountID else { return }
            self.stickyBindings.removeValue(forKey: stickyKey)
        }
    }

    private func forwardResponsesRequest(_ request: ParsedGatewayRequest, on connection: NWConnection) async {
        let snapshot = self.snapshot()
        let stickyKey = self.stickySessionKey(for: request.headers)
        let candidates = self.candidates(for: snapshot, stickyKey: stickyKey)

        guard candidates.isEmpty == false else {
            self.sendJSONResponse(
                on: connection,
                statusCode: 503,
                body: #"{"error":{"message":"aggregate gateway unavailable: no routable OpenAI account"}}"#
            )
            return
        }

        for (index, account) in candidates.enumerated() {
            do {
                let result = try await self.proxyPOSTResponses(request, account: account)
                if self.shouldRetry(statusCode: result.response.statusCode),
                   index < candidates.count - 1 {
                    self.clearBinding(stickyKey: stickyKey, accountID: account.accountId)
                    continue
                }

                self.bind(stickyKey: stickyKey, accountID: account.accountId)
                try await self.stream(result: result, to: connection)
                return
            } catch {
                if index == candidates.count - 1 {
                    self.sendJSONResponse(
                        on: connection,
                        statusCode: 502,
                        body: #"{"error":{"message":"codexbar gateway failed to reach OpenAI upstream"}}"#
                    )
                }
            }
        }
    }

    private func proxyPOSTResponses(
        _ request: ParsedGatewayRequest,
        account: TokenAccount
    ) async throws -> (response: HTTPURLResponse, bytes: URLSession.AsyncBytes) {
        var upstreamRequest = URLRequest(url: OpenAIAccountGatewayConfiguration.upstreamResponsesURL)
        upstreamRequest.httpMethod = "POST"
        upstreamRequest.httpBody = request.body

        for (name, value) in request.headers {
            switch name {
            case "host", "content-length", "authorization", "chatgpt-account-id", "connection":
                continue
            default:
                upstreamRequest.setValue(value, forHTTPHeaderField: name)
            }
        }

        upstreamRequest.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "authorization")
        upstreamRequest.setValue(account.openAIAccountId, forHTTPHeaderField: "chatgpt-account-id")

        let (bytes, response) = try await self.urlSession.bytes(for: upstreamRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return (httpResponse, bytes)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 403 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private func stream(
        result: (response: HTTPURLResponse, bytes: URLSession.AsyncBytes),
        to connection: NWConnection
    ) async throws {
        let headers = self.renderResponseHeaders(from: result.response)
        try await self.send(Data(headers.utf8), on: connection)

        var buffer = Data()
        for try await byte in result.bytes {
            buffer.append(byte)
            if buffer.count >= 8192 {
                try await self.send(buffer, on: connection)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if buffer.isEmpty == false {
            try await self.send(buffer, on: connection)
        }

        connection.cancel()
    }

    private func renderResponseHeaders(from response: HTTPURLResponse) -> String {
        var lines = ["HTTP/1.1 \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode).capitalized)"]

        for (nameAny, valueAny) in response.allHeaderFields {
            guard let name = nameAny as? String,
                  let value = valueAny as? String else {
                continue
            }
            let lowercased = name.lowercased()
            if lowercased == "content-length" || lowercased == "transfer-encoding" || lowercased == "connection" {
                continue
            }
            lines.append("\(name): \(value)")
        }

        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private func sendJSONResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let data = Data(body.utf8)
        let head = [
            "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)",
            "Content-Type: application/json",
            "Content-Length: \(data.count)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
