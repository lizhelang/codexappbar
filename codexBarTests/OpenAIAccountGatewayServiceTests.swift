import Foundation
import XCTest

final class OpenAIAccountGatewayServiceTests: CodexBarTestCase {
    func testResponsesProbeGETBuildsWebSocketHandshakeWhenHeadersAndAccountExist() async throws {
        let service = OpenAIAccountGatewayService(
            urlSession: self.makeMockSession(),
            runtimeConfiguration: .init(
                host: "127.0.0.1",
                port: 1456,
                upstreamResponsesURL: URL(string: "https://example.invalid/v1/responses")!
            )
        )

        let account = TokenAccount(
            email: "alpha@example.com",
            accountId: "acct-alpha",
            openAIAccountId: "openai-alpha",
            accessToken: "token-alpha",
            refreshToken: "refresh-alpha",
            idToken: "id-alpha",
            planType: "plus",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10
        )
        service.updateState(
            accounts: [account],
            quotaSortSettings: .init(),
            accountUsageMode: .aggregateGateway
        )

        let request = try XCTUnwrap(
            service.parseRequestForTesting(
                from: self.rawRequest(
                    lines: [
                        "GET /v1/responses HTTP/1.1",
                        "Host: 127.0.0.1:1456",
                        "Connection: Upgrade",
                        "Upgrade: websocket",
                        "Sec-WebSocket-Version: 13",
                        "Sec-WebSocket-Key: dGVzdC1jb2RleGJhcg==",
                    ]
                )
            )
        )

        let response = service.webSocketUpgradeProbeForTesting(request: request)

        XCTAssertEqual(response.statusCode, 101)
        XCTAssertEqual(
            response.headers["Sec-WebSocket-Accept"],
            "jbsNjU5oGfarrt3XvjT/Dv7jeRU="
        )
        XCTAssertEqual(response.headers["Upgrade"], "websocket")
        XCTAssertEqual(response.headers["Connection"], "Upgrade")
        XCTAssertTrue(response.body.isEmpty)
    }

    func testResponsesPOSTFailoverRebindsStickySessionAndRewritesHeaders() async throws {
        let service = OpenAIAccountGatewayService(
            urlSession: self.makeMockSession(),
            runtimeConfiguration: .init(
                host: "127.0.0.1",
                port: 1456,
                upstreamResponsesURL: URL(string: "https://example.invalid/v1/responses")!
            )
        )

        let primary = TokenAccount(
            email: "alpha@example.com",
            accountId: "acct-alpha",
            openAIAccountId: "openai-alpha",
            accessToken: "token-alpha",
            refreshToken: "refresh-alpha",
            idToken: "id-alpha",
            planType: "plus",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10
        )
        let secondary = TokenAccount(
            email: "beta@example.com",
            accountId: "acct-beta",
            openAIAccountId: "openai-beta",
            accessToken: "token-beta",
            refreshToken: "refresh-beta",
            idToken: "id-beta",
            planType: "free",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10
        )

        service.updateState(
            accounts: [primary, secondary],
            quotaSortSettings: .init(),
            accountUsageMode: .aggregateGateway
        )

        let observedQueue = DispatchQueue(label: "OpenAIAccountGatewayServiceTests.observed")
        var forwardedAuthorizations: [String] = []
        var forwardedAccountIDs: [String] = []
        var forwardedBodies: [String] = []

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "authorization") ?? ""
            let accountID = request.value(forHTTPHeaderField: "chatgpt-account-id") ?? ""
            let bodyData =
                request.httpBody ??
                (URLProtocol.property(
                    forKey: OpenAIAccountGatewayService.mockRequestBodyPropertyKey,
                    in: request
                ) as? Data) ??
                Data()
            let body = String(data: bodyData, encoding: .utf8) ?? ""

            observedQueue.sync {
                forwardedAuthorizations.append(authorization)
                forwardedAccountIDs.append(accountID)
                forwardedBodies.append(body)
            }

            let statusCode: Int
            let payload: String
            switch authorization {
            case "Bearer token-alpha":
                statusCode = 429
                payload = "retry alpha"
            case "Bearer token-beta":
                statusCode = 200
                payload = "data: ok\n\n"
            default:
                statusCode = 500
                payload = "unexpected"
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(payload.utf8))
        }

        let firstResponse = try await self.postToGateway(
            service: service,
            stickyKey: "session-1",
            body: #"{"input":"hello"}"#
        )
        let secondResponse = try await self.postToGateway(
            service: service,
            stickyKey: "session-1",
            body: #"{"input":"again"}"#
        )

        XCTAssertEqual(firstResponse.statusCode, 200)
        XCTAssertEqual(firstResponse.body, "data: ok\n\n")
        XCTAssertEqual(secondResponse.statusCode, 200)
        XCTAssertEqual(secondResponse.body, "data: ok\n\n")

        let observed = observedQueue.sync {
            (
                forwardedAuthorizations,
                forwardedAccountIDs,
                forwardedBodies
            )
        }

        XCTAssertEqual(
            observed.0,
            ["Bearer token-alpha", "Bearer token-beta", "Bearer token-beta"]
        )
        XCTAssertEqual(
            observed.1,
            ["openai-alpha", "openai-beta", "openai-beta"]
        )
        XCTAssertEqual(
            observed.2,
            [#"{"input":"hello"}"#, #"{"input":"hello"}"#, #"{"input":"again"}"#]
        )
    }

    private func postToGateway(
        service: OpenAIAccountGatewayService,
        stickyKey: String,
        body: String
    ) async throws -> (statusCode: Int, body: String) {
        let request = try XCTUnwrap(
            service.parseRequestForTesting(
                from: self.rawRequest(
                    lines: [
                        "POST /v1/responses HTTP/1.1",
                        "Host: 127.0.0.1:1456",
                        "Content-Type: application/json",
                        "Authorization: Bearer \(OpenAIAccountGatewayConfiguration.apiKey)",
                        "chatgpt-account-id: local-placeholder",
                        "x-client-request-id: \(stickyKey)",
                        "Content-Length: \(Data(body.utf8).count)",
                        "Connection: close",
                    ],
                    body: body
                )
            )
        )

        let response = try await service.postResponsesProbeForTesting(request: request)
        return (response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
    }

    private func rawRequest(lines: [String], body: String = "") -> Data {
        var text = lines.joined(separator: "\r\n")
        text += "\r\n\r\n"
        text += body
        return Data(text.utf8)
    }
}
