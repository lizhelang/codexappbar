import Foundation

enum LocalhostOAuthCallbackServerError: LocalizedError {
    case socketCreationFailed
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "Failed to create localhost OAuth callback socket."
        case .bindFailed(let code):
            return "Failed to bind localhost OAuth callback listener (errno \(code))."
        case .listenFailed(let code):
            return "Failed to listen for localhost OAuth callback (errno \(code))."
        }
    }
}

final class LocalhostOAuthCallbackServer {
    let port: UInt16
    let callbackPath: String

    private let queue = DispatchQueue(label: "lzl.codexbar.oauth-callback-server")
    private let onCallback: @MainActor (String) -> Void

    private var isRunning = false
    private var serverFd: Int32 = -1

    init(
        port: UInt16 = 1455,
        callbackPath: String = "/auth/callback",
        onCallback: @escaping @MainActor (String) -> Void
    ) {
        self.port = port
        self.callbackPath = callbackPath
        self.onCallback = onCallback
    }

    func start() throws {
        self.stop()

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LocalhostOAuthCallbackServerError.socketCreationFailed
        }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = self.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw LocalhostOAuthCallbackServerError.bindFailed(errno: code)
        }

        guard Darwin.listen(fd, 5) == 0 else {
            let code = errno
            close(fd)
            throw LocalhostOAuthCallbackServerError.listenFailed(errno: code)
        }

        self.serverFd = fd
        self.isRunning = true

        self.queue.async { [weak self] in
            self?.acceptLoop(serverFd: fd)
        }
    }

    func stop() {
        self.isRunning = false
        if self.serverFd >= 0 {
            shutdown(self.serverFd, SHUT_RDWR)
            close(self.serverFd)
            self.serverFd = -1
        }
    }

    private func acceptLoop(serverFd: Int32) {
        defer {
            if self.serverFd == serverFd {
                self.serverFd = -1
            }
            close(serverFd)
        }

        while self.isRunning {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                if self.isRunning == false { break }
                continue
            }
            self.handle(clientFd: clientFd)
        }
    }

    private func handle(clientFd: Int32) {
        defer { close(clientFd) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(clientFd, &buffer, buffer.count - 1, 0)
        guard bytesRead > 0,
              let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) else {
            self.write(response: Self.httpResponse(status: "400 Bad Request", body: "Invalid callback request."), to: clientFd)
            return
        }

        guard let callbackURL = Self.callbackURL(
            from: request,
            host: "localhost",
            port: self.port,
            callbackPath: self.callbackPath
        ) else {
            self.write(response: Self.httpResponse(status: "404 Not Found", body: "Callback route not found."), to: clientFd)
            return
        }

        self.write(response: Self.successResponse, to: clientFd)
        self.stop()

        Task { @MainActor [callbackURL, onCallback] in
            onCallback(callbackURL)
        }
    }

    private func write(response: Data, to clientFd: Int32) {
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = send(clientFd, baseAddress, rawBuffer.count, 0)
        }
    }

    static func callbackURL(
        from request: String,
        host: String = "localhost",
        port: UInt16 = 1455,
        callbackPath: String = "/auth/callback"
    ) -> String? {
        guard let line = request.components(separatedBy: "\r\n").first,
              line.hasPrefix("GET ") else { return nil }

        let parts = line.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let pathAndQuery = parts[1]
        guard pathAndQuery.hasPrefix(callbackPath) else { return nil }
        return "http://\(host):\(port)\(pathAndQuery)"
    }

    private static func httpResponse(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")

        var data = Data(headers.utf8)
        data.append(bodyData)
        return data
    }

    private static let successResponse = LocalhostOAuthCallbackServer.httpResponse(
        status: "200 OK",
        body: """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Codexbar Login Received</title>
          <style>
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background: #111;
              color: #f5f5f5;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            .card {
              width: min(92vw, 420px);
              padding: 28px 24px;
              border-radius: 18px;
              background: #1b1b1b;
              border: 1px solid #2c2c2c;
              box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
            }
            h1 {
              margin: 0 0 10px;
              font-size: 22px;
            }
            p {
              margin: 0;
              color: #b7b7b7;
              line-height: 1.5;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Login received</h1>
            <p>Codexbar captured the localhost callback. You can return to the app now.</p>
          </div>
        </body>
        </html>
        """
    )
}
