import XCTest

final class CodexBarOpenAIAccountUsageModeTests: XCTestCase {
    private var originalLanguageOverride: Bool?

    override func setUp() {
        super.setUp()
        self.originalLanguageOverride = L.languageOverride
    }

    override func tearDown() {
        L.languageOverride = self.originalLanguageOverride
        super.tearDown()
    }

    func testMenuToggleTitlesUseRequestedChineseCopy() {
        L.languageOverride = true

        XCTAssertEqual(CodexBarOpenAIAccountUsageMode.switchAccount.menuToggleTitle, "切换账号")
        XCTAssertEqual(CodexBarOpenAIAccountUsageMode.aggregateGateway.menuToggleTitle, "聚合api")
    }

    func testUsageModeOrderKeepsSwitchOnTheLeftAndAggregateOnTheRight() {
        XCTAssertEqual(
            CodexBarOpenAIAccountUsageMode.allCases,
            [.switchAccount, .aggregateGateway]
        )
    }
}
