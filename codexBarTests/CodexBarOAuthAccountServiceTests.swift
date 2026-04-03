import Foundation
import XCTest

final class CodexBarOAuthAccountServiceTests: CodexBarTestCase {
    func testImportActivatedAccountSynchronizesAuthAndConfig() throws {
        let service = CodexBarOAuthAccountService()
        let account = TokenAccount(
            email: "alice@example.com",
            accountId: "acct_alice",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token"
        )

        let result = try service.importAccount(account, activate: true)

        XCTAssertTrue(result.active)
        XCTAssertTrue(result.synchronized)

        let authData = try Data(contentsOf: CodexPaths.authURL)
        let authObject = try XCTUnwrap(JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let tokens = try XCTUnwrap(authObject["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["account_id"] as? String, "acct_alice")
        XCTAssertEqual(tokens["access_token"] as? String, "access-token")

        let configText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
        XCTAssertTrue(configText.contains("model_provider = \"openai\""))
        XCTAssertTrue(configText.contains("model = \"gpt-5.4\""))
    }

    func testActivateAccountUpdatesActiveSelection() throws {
        let service = CodexBarOAuthAccountService()

        _ = try service.importAccount(
            TokenAccount(
                email: "first@example.com",
                accountId: "acct_first",
                accessToken: "access-1",
                refreshToken: "refresh-1",
                idToken: "id-1"
            ),
            activate: true
        )
        _ = try service.importAccount(
            TokenAccount(
                email: "second@example.com",
                accountId: "acct_second",
                accessToken: "access-2",
                refreshToken: "refresh-2",
                idToken: "id-2"
            ),
            activate: false
        )

        let activation = try service.activateAccount(accountID: "acct_second")
        XCTAssertTrue(activation.active)

        let accounts = try service.listAccounts()
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_second" })?.active, true)
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_first" })?.active, false)
    }
}
