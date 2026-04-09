import XCTest

final class OpenAIAccountPresentationTests: XCTestCase {
    private var originalLanguageOverride: Bool?

    override func setUp() {
        super.setUp()
        self.originalLanguageOverride = L.languageOverride
        L.languageOverride = false
    }

    override func tearDown() {
        L.languageOverride = self.originalLanguageOverride
        super.tearDown()
    }

    func testRowStateShowsUseActionWhenAccountIsNotNextUseTarget() {
        let account = self.makeAccount(accountId: "acct_idle", isActive: false)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: OpenAIRunningThreadAttribution.Summary.empty
        )

        XCTAssertTrue(state.showsUseAction)
        XCTAssertEqual(state.useActionTitle, "Use")
        XCTAssertNil(state.runningThreadBadgeTitle)
    }

    func testRowStateShowsSelectedNextUseStateWithoutUseAction() {
        let account = self.makeAccount(accountId: "acct_next", isActive: true)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: OpenAIRunningThreadAttribution.Summary.empty
        )

        XCTAssertTrue(state.isNextUseTarget)
        XCTAssertFalse(state.showsUseAction)
    }

    func testRowStateShowsRunningThreadBadgeWhenThreadsAreAttributed() {
        let account = self.makeAccount(accountId: "acct_busy", isActive: false)
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_busy": 2],
            unknownThreadCount: 0
        )

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: summary
        )

        XCTAssertEqual(state.runningThreadCount, 2)
        XCTAssertEqual(state.runningThreadBadgeTitle, "Running · 2 threads")
    }

    func testNextUseAndRunningThreadsCanCoexistOnSameAccount() {
        let account = self.makeAccount(accountId: "acct_dual", isActive: true)
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_dual": 2],
            unknownThreadCount: 0
        )

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: summary
        )

        XCTAssertTrue(state.isNextUseTarget)
        XCTAssertEqual(state.runningThreadCount, 2)
        XCTAssertFalse(state.showsUseAction)
        XCTAssertEqual(state.runningThreadBadgeTitle, "Running · 2 threads")
    }

    func testUnavailableSummaryHidesBadgeAndShowsUnavailableText() {
        let account = self.makeAccount(accountId: "acct_busy", isActive: false)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: .unavailable
        )
        let summaryText = OpenAIAccountPresentation.runningThreadSummaryText(summary: .unavailable)

        XCTAssertEqual(state.runningThreadCount, 0)
        XCTAssertNil(state.runningThreadBadgeTitle)
        XCTAssertEqual(summaryText, "Running status unavailable")
    }

    func testUnavailableAttributionShowsRuntimeLogInitializationHint() {
        let logsDatabaseName = CodexPaths.logsSQLiteURL.lastPathComponent
        let attribution = OpenAIRunningThreadAttribution(
            threads: [],
            summary: .unavailable,
            recentActivityWindow: 5,
            diagnosticMessage: "runtime database missing table: \(logsDatabaseName).logs",
            unavailableReason: .missingTable(database: logsDatabaseName, table: "logs")
        )

        let summaryText = OpenAIAccountPresentation.runningThreadSummaryText(
            attribution: attribution
        )

        XCTAssertEqual(
            summaryText,
            "Running status unavailable (runtime logs not initialized)"
        )
    }

    func testSummaryTextIncludesUnattributedRunningThreads() {
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_busy": 2],
            unknownThreadCount: 1
        )

        let text = OpenAIAccountPresentation.runningThreadSummaryText(summary: summary)

        XCTAssertEqual(text, "Running · 3 threads / 1 account · 1 unattributed thread")
    }

    func testManualActivationContextActionsExposeTwoOverridesAndMarkUpdateConfigDefault() {
        let actions = OpenAIAccountPresentation.manualActivationContextActions(
            defaultBehavior: .updateConfigOnly
        )

        XCTAssertEqual(OpenAIAccountPresentation.primaryManualActivationTrigger, .primaryTap)
        XCTAssertEqual(actions.map(\.behavior), [.updateConfigOnly, .launchNewInstance])
        XCTAssertEqual(
            actions.map(\.trigger),
            [.contextOverride(.updateConfigOnly), .contextOverride(.launchNewInstance)]
        )
        XCTAssertEqual(
            actions.map(\.title),
            ["Update Config Only (This Time)", "Launch New Instance (This Time)"]
        )
        XCTAssertEqual(actions.filter(\.isDefault).map(\.behavior), [.updateConfigOnly])
    }

    func testManualActivationContextActionsMarkLaunchDefault() {
        let actions = OpenAIAccountPresentation.manualActivationContextActions(
            defaultBehavior: .launchNewInstance
        )

        XCTAssertEqual(actions.filter(\.isDefault).map(\.behavior), [.launchNewInstance])
    }

    private func makeAccount(accountId: String, isActive: Bool) -> TokenAccount {
        TokenAccount(
            email: "\(accountId)@example.com",
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)",
            isActive: isActive
        )
    }
}
