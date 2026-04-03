import Foundation
import XCTest

final class OpenAIOAuthFlowServiceTests: CodexBarTestCase {
    func testStartFlowPersistsRecoverableFlow() throws {
        let service = OpenAIOAuthFlowService(session: self.makeMockSession())

        let started = try service.startFlow()
        XCTAssertFalse(started.flowID.isEmpty)
        XCTAssertTrue(started.authURL.contains("code_challenge="))

        let flowURL = CodexPaths.oauthFlowsDirectoryURL.appendingPathComponent("\(started.flowID).json")
        let data = try Data(contentsOf: flowURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let flow = try decoder.decode(PendingOAuthFlow.self, from: data)

        XCTAssertEqual(flow.flowID, started.flowID)
        XCTAssertFalse(flow.codeVerifier.isEmpty)
        XCTAssertFalse(flow.expectedState.isEmpty)
    }

    func testCompleteFlowAcceptsCallbackURLAndCleansFlow() async throws {
        let accessToken = try self.makeJWT(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_openai_alice",
                "chatgpt_plan_type": "pro",
            ],
        ])
        let idToken = try self.makeJWT(payload: [
            "email": "alice@example.com",
        ])

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "access_token": accessToken,
                "refresh_token": "refresh-token",
                "id_token": idToken,
            ], options: [.sortedKeys])
            return (response, data)
        }

        let service = OpenAIOAuthFlowService(session: self.makeMockSession())
        let started = try service.startFlow()
        let state = URLComponents(string: started.authURL)?
            .queryItems?
            .first(where: { $0.name == "state" })?
            .value

        let result = try await service.completeFlow(
            flowID: started.flowID,
            callbackURL: "http://localhost:1455/auth/callback?code=oauth-code&state=\(state ?? "")",
            activate: true
        )

        XCTAssertEqual(result.account.accountId, "acct_openai_alice")
        XCTAssertEqual(result.account.email, "alice@example.com")
        XCTAssertTrue(result.active)
        XCTAssertTrue(result.synchronized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexPaths.oauthFlowsDirectoryURL.appendingPathComponent("\(started.flowID).json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexPaths.authURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexPaths.configTomlURL.path))
    }

    func testCompleteFlowAcceptsBareCodeWhenStateDiffers() async throws {
        let accessToken = try self.makeJWT(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_state_mismatch",
                "chatgpt_plan_type": "plus",
            ],
        ])
        let idToken = try self.makeJWT(payload: [
            "email": "mismatch@example.com",
        ])

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "access_token": accessToken,
                "refresh_token": "refresh-token",
                "id_token": idToken,
            ], options: [.sortedKeys])
            return (response, data)
        }

        let service = OpenAIOAuthFlowService(session: self.makeMockSession())
        let started = try service.startFlow()

        let result = try await service.completeFlow(
            flowID: started.flowID,
            code: "oauth-code",
            returnedState: "different-state",
            activate: false
        )

        XCTAssertEqual(result.account.accountId, "acct_state_mismatch")
        XCTAssertEqual(result.account.email, "mismatch@example.com")
        XCTAssertFalse(result.active)
    }
}
