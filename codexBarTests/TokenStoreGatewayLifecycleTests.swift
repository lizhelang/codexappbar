import Foundation
import XCTest

@MainActor
final class TokenStoreGatewayLifecycleTests: CodexBarTestCase {
    func testSwitchModeInitializationKeepsGatewayStopped() {
        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy()

        _ = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { [] }
        )

        XCTAssertEqual(gateway.startCount, 0)
        XCTAssertEqual(gateway.stopCount, 1)
        XCTAssertEqual(gateway.updatedModes, [.switchAccount])
    }

    func testAggregateModeInitializationStartsGateway() throws {
        var config = CodexBarConfig()
        config.openAI.accountUsageMode = .aggregateGateway
        try self.writeConfig(config)

        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy()

        _ = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { [] }
        )

        XCTAssertEqual(gateway.startCount, 1)
        XCTAssertEqual(gateway.stopCount, 0)
        XCTAssertEqual(gateway.updatedModes, [.aggregateGateway])
    }

    func testUpdatingUsageModeStartsAndStopsGateway() throws {
        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy()
        let store = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { [] }
        )
        let account = try self.makeOAuthAccount(
            accountID: "acct-gateway",
            email: "gateway@example.com"
        )

        store.addOrUpdate(account)
        try store.activate(account)

        let initialStopCount = gateway.stopCount
        let initialUpdateCount = gateway.updatedModes.count

        try store.updateOpenAIAccountUsageMode(.aggregateGateway)
        XCTAssertEqual(gateway.startCount, 1)
        XCTAssertEqual(gateway.stopCount, initialStopCount)
        XCTAssertEqual(gateway.updatedModes.suffix(1).first, .aggregateGateway)

        try store.updateOpenAIAccountUsageMode(.switchAccount)
        XCTAssertEqual(gateway.startCount, 1)
        XCTAssertEqual(gateway.stopCount, initialStopCount + 1)
        XCTAssertEqual(gateway.updatedModes.count, initialUpdateCount + 2)
        XCTAssertEqual(gateway.updatedModes.suffix(1).first, .switchAccount)
    }

    func testAggregateLeaseKeepsGatewayRunningAfterSwitchModeChange() throws {
        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy()
        var runningPIDs: Set<pid_t> = [101, 202]
        let account = try self.makeOAuthAccount(
            accountID: "acct-lease",
            email: "lease@example.com"
        )
        let storedAccount = CodexBarProviderAccount.fromTokenAccount(account, existingID: account.accountId)
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: storedAccount.id,
            accounts: [storedAccount]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: storedAccount.id),
            openAI: CodexBarOpenAISettings(accountUsageMode: .aggregateGateway),
            providers: [provider]
        )
        try self.writeConfig(config)

        let store = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { runningPIDs }
        )

        try store.updateOpenAIAccountUsageMode(.switchAccount)

        XCTAssertEqual(store.config.openAI.accountUsageMode, .switchAccount)
        XCTAssertEqual(leaseStore.savedProcessIDs, runningPIDs)
        XCTAssertEqual(gateway.stopCount, 0)
        XCTAssertEqual(gateway.updatedModes.suffix(1).first, .aggregateGateway)
    }

    func testGatewayStopsOnceLeasedAggregateProcessesExit() {
        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy(initialProcessIDs: [404])
        var runningPIDs: Set<pid_t> = [404]

        let store = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { runningPIDs }
        )

        XCTAssertEqual(gateway.updatedModes.suffix(1).first, .aggregateGateway)

        runningPIDs = []
        store.markActiveAccount()

        XCTAssertTrue(leaseStore.cleared)
        XCTAssertEqual(gateway.updatedModes.suffix(1).first, .switchAccount)
        XCTAssertEqual(gateway.stopCount, 1)
    }

    func testPersistedAggregateLeaseRestoresGatewayAfterRestart() {
        let gateway = OpenAIAccountGatewayControllerSpy()
        let leaseStore = OpenAIAggregateGatewayLeaseStoreSpy(initialProcessIDs: [303])

        _ = TokenStore(
            openAIAccountGatewayService: gateway,
            aggregateGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { [303] }
        )

        XCTAssertEqual(gateway.startCount, 1)
        XCTAssertEqual(gateway.stopCount, 0)
        XCTAssertEqual(gateway.updatedModes, [.aggregateGateway])
    }

    private func writeConfig(_ config: CodexBarConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try CodexPaths.writeSecureFile(data, to: CodexPaths.barConfigURL)
    }
}

private final class OpenAIAccountGatewayControllerSpy: OpenAIAccountGatewayControlling {
    var startCount = 0
    var stopCount = 0
    var updatedModes: [CodexBarOpenAIAccountUsageMode] = []

    func startIfNeeded() {
        self.startCount += 1
    }

    func stop() {
        self.stopCount += 1
    }

    func updateState(
        accounts: [TokenAccount],
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        accountUsageMode: CodexBarOpenAIAccountUsageMode
    ) {
        self.updatedModes.append(accountUsageMode)
    }
}

private final class OpenAIAggregateGatewayLeaseStoreSpy: OpenAIAggregateGatewayLeaseStoring {
    private(set) var savedProcessIDs: Set<pid_t> = []
    private(set) var cleared = false
    private let initialProcessIDs: Set<pid_t>

    init(initialProcessIDs: Set<pid_t> = []) {
        self.initialProcessIDs = initialProcessIDs
    }

    func loadProcessIDs() -> Set<pid_t> {
        self.initialProcessIDs
    }

    func saveProcessIDs(_ processIDs: Set<pid_t>) {
        self.savedProcessIDs = processIDs
        self.cleared = false
    }

    func clear() {
        self.savedProcessIDs = []
        self.cleared = true
    }
}
