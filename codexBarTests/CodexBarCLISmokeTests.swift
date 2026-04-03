import Foundation
import XCTest

final class CodexBarCLISmokeTests: CodexBarTestCase {
    func testLoginStartJSONOutputsAuthURLWithoutTokens() async throws {
        let io = TestCLIIO()
        let runner = CodexBarCLICommandRunner(
            flowService: OpenAIOAuthFlowService(session: self.makeMockSession()),
            io: io
        )

        let exitCode = await runner.run(arguments: ["openai", "login", "start", "--json"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(io.stdout.contains("\"flow_id\""))
        XCTAssertTrue(io.stdout.contains("\"auth_url\""))
        XCTAssertFalse(io.stdout.contains("access_token"))
    }

    func testLoginCompleteJSONImportsAccount() async throws {
        let accessToken = try self.makeJWT(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_cli",
                "chatgpt_plan_type": "pro",
            ],
        ])
        let idToken = try self.makeJWT(payload: [
            "email": "cli@example.com",
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

        let flowService = OpenAIOAuthFlowService(session: self.makeMockSession())
        let started = try flowService.startFlow()
        let io = TestCLIIO()
        let runner = CodexBarCLICommandRunner(flowService: flowService, io: io)

        let exitCode = await runner.run(arguments: [
            "openai", "login", "complete",
            "--flow-id", started.flowID,
            "--code", "oauth-code",
            "--json",
        ])

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(io.stdout.contains("\"account_id\""))
        XCTAssertTrue(io.stdout.contains("\"cli@example.com\""))
        XCTAssertTrue(io.stdout.contains("\"active\" : true"))
    }

    func testAccountsListAndActivateCommands() async throws {
        let accountService = CodexBarOAuthAccountService()
        _ = try accountService.importAccount(
            TokenAccount(
                email: "first@example.com",
                accountId: "acct_first",
                accessToken: "access-1",
                refreshToken: "refresh-1",
                idToken: "id-1"
            ),
            activate: true
        )
        _ = try accountService.importAccount(
            TokenAccount(
                email: "second@example.com",
                accountId: "acct_second",
                accessToken: "access-2",
                refreshToken: "refresh-2",
                idToken: "id-2"
            ),
            activate: false
        )

        let listIO = TestCLIIO()
        let runner = CodexBarCLICommandRunner(accountService: accountService, io: listIO)
        let listExitCode = await runner.run(arguments: ["accounts", "list", "--json"])
        XCTAssertEqual(listExitCode, 0)
        XCTAssertTrue(listIO.stdout.contains("\"acct_first\""))
        XCTAssertTrue(listIO.stdout.contains("\"acct_second\""))

        let activateIO = TestCLIIO()
        let activateRunner = CodexBarCLICommandRunner(accountService: accountService, io: activateIO)
        let activateExitCode = await activateRunner.run(arguments: ["accounts", "activate", "--account-id", "acct_second", "--json"])
        XCTAssertEqual(activateExitCode, 0)
        XCTAssertTrue(activateIO.stdout.contains("\"acct_second\""))
        XCTAssertTrue(activateIO.stdout.contains("\"active\" : true"))
    }
}
