import XCTest

@MainActor
final class SettingsWindowCoordinatorTests: XCTestCase {
    func testSwitchingPagesKeepsDraftAcrossEdits() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .usage
        coordinator.update(\.popupAlertThresholdPercent, to: 35, field: .popupAlertThresholdPercent)
        coordinator.selectedPage = .recommendationPrompt
        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)
        coordinator.selectedPage = .accounts

        XCTAssertEqual(coordinator.draft.accountOrderingMode, .manual)
        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .launchNewInstance)
        coordinator.selectedPage = .usage
        XCTAssertEqual(coordinator.draft.popupAlertThresholdPercent, 35)
        coordinator.selectedPage = .recommendationPrompt
        XCTAssertEqual(coordinator.draft.autoRoutingPromptMode, .remindOnly)
    }

    func testSaveEmitsChangedDomainRequestsAndReopenReflectsSavedValues() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        coordinator.setAccountOrder(["acct_beta", "acct_alpha"])
        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .usage
        coordinator.update(\.popupAlertThresholdPercent, to: 30, field: .popupAlertThresholdPercent)
        coordinator.selectedPage = .recommendationPrompt
        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)

        let requests = try coordinator.save(using: sink)

        XCTAssertEqual(sink.appliedRequests.count, 1)
        XCTAssertEqual(
            requests.openAIAccount,
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_beta", "acct_alpha"],
                accountOrderingMode: .manual,
                manualActivationBehavior: .launchNewInstance
            )
        )
        XCTAssertEqual(
            requests.openAIUsage,
            OpenAIUsageSettingsUpdate(
                popupAlertThresholdPercent: 30,
                usageDisplayMode: .used,
                plusRelativeWeight: 10,
                teamRelativeToPlusMultiplier: 1.5
            )
        )
        XCTAssertEqual(
            requests.autoRoutingPrompt,
            AutoRoutingPromptSettingsUpdate(promptMode: .remindOnly)
        )
        XCTAssertNil(requests.desktop)

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        XCTAssertEqual(reopened.draft.accountOrder, ["acct_beta", "acct_alpha"])
        XCTAssertEqual(reopened.draft.accountOrderingMode, .manual)
        XCTAssertEqual(reopened.draft.manualActivationBehavior, .launchNewInstance)
        XCTAssertEqual(reopened.draft.popupAlertThresholdPercent, 30)
        XCTAssertEqual(reopened.draft.autoRoutingPromptMode, .remindOnly)
    }

    func testCancelRollsBackAcrossPagesAndDoesNotTriggerRequests() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let baseConfig = self.makeConfig()
        let sink = TestSettingsSaveSink(config: baseConfig)
        let coordinator = SettingsWindowCoordinator(
            config: baseConfig,
            accounts: accounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .usage
        coordinator.update(\.popupAlertThresholdPercent, to: 45, field: .popupAlertThresholdPercent)
        coordinator.selectedPage = .recommendationPrompt
        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)

        coordinator.cancel()

        XCTAssertTrue(sink.appliedRequests.isEmpty)
        XCTAssertEqual(coordinator.draft, SettingsWindowDraft(config: baseConfig, accounts: accounts))

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        XCTAssertEqual(reopened.draft, SettingsWindowDraft(config: baseConfig, accounts: accounts))
    }

    func testSaveAndCloseClosesWindowAfterSuccessfulSave() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        var closeCount = 0

        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)
        coordinator.saveAndClose(using: sink) {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(sink.appliedRequests.count, 1)
    }

    func testCancelAndCloseDoesNotSaveButClosesWindow() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        var closeCount = 0

        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)
        coordinator.cancelAndClose {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(sink.appliedRequests.isEmpty)
        XCTAssertEqual(coordinator.draft.autoRoutingPromptMode, .launchNewInstance)
    }

    func testSaveAndCloseKeepsWindowOpenWhenSaveFails() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )
        let sink = FailingSettingsSaveSink()
        var closeCount = 0

        coordinator.update(\.autoRoutingPromptMode, to: .remindOnly, field: .autoRoutingPromptMode)
        coordinator.saveAndClose(using: sink) {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(coordinator.validationMessage, "save failed")
    }

    func testReconcileExternalStateRefreshesUntouchedFieldsAndPreservesEditedFields() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)

        var externalConfig = self.makeConfig()
        externalConfig.openAI.accountOrderingMode = .manual
        externalConfig.autoRouting.promptMode = .remindOnly
        externalConfig.openAI.manualActivationBehavior = .updateConfigOnly

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: initialAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrderingMode, .manual)
        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .launchNewInstance)
        XCTAssertEqual(coordinator.draft.autoRoutingPromptMode, .remindOnly)
    }

    func testReconcileExternalStateKeepsExplicitlyEditedFieldEvenIfValueMatchesOriginalBaseline() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.update(\.manualActivationBehavior, to: .updateConfigOnly, field: .manualActivationBehavior)

        var externalConfig = self.makeConfig()
        externalConfig.openAI.manualActivationBehavior = .launchNewInstance

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: initialAccounts
        )

        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .updateConfigOnly)
        XCTAssertEqual(
            coordinator.makeSaveRequests().openAIAccount,
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_alpha", "acct_beta"],
                accountOrderingMode: .quotaSort,
                manualActivationBehavior: .updateConfigOnly
            )
        )
    }

    func testReconcileExternalStateMergesNewAccountsIntoEditedOrder() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )
        coordinator.setAccountOrder(["acct_beta", "acct_alpha"])

        var externalConfig = self.makeConfig()
        externalConfig.setOpenAIAccountOrder(["acct_alpha", "acct_beta", "acct_gamma"])
        let updatedAccounts = initialAccounts + [
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: updatedAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrder, ["acct_beta", "acct_alpha", "acct_gamma"])
        XCTAssertEqual(coordinator.orderedAccounts.map(\.id), ["acct_beta", "acct_alpha", "acct_gamma"])
    }

    func testReconcileExternalStateDropsRemovedAccountsFromEditedOrder() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(accountOrder: ["acct_alpha", "acct_beta", "acct_gamma"]),
            accounts: initialAccounts
        )
        coordinator.setAccountOrder(["acct_gamma", "acct_beta", "acct_alpha"])

        let updatedAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]
        let externalConfig = self.makeConfig(accountOrder: ["acct_alpha", "acct_gamma"])

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: updatedAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrder, ["acct_gamma", "acct_alpha"])
        XCTAssertEqual(coordinator.orderedAccounts.map(\.id), ["acct_gamma", "acct_alpha"])
    }

    private func makeConfig(
        accountOrder: [String] = ["acct_alpha", "acct_beta"],
        accountOrderingMode: CodexBarOpenAIAccountOrderingMode = .quotaSort
    ) -> CodexBarConfig {
        let alpha = CodexBarProviderAccount(
            id: "acct_alpha",
            kind: .oauthTokens,
            label: "alpha@example.com",
            email: "alpha@example.com",
            openAIAccountId: "acct_alpha",
            accessToken: "access-alpha",
            refreshToken: "refresh-alpha",
            idToken: "id-alpha"
        )
        let beta = CodexBarProviderAccount(
            id: "acct_beta",
            kind: .oauthTokens,
            label: "beta@example.com",
            email: "beta@example.com",
            openAIAccountId: "acct_beta",
            accessToken: "access-beta",
            refreshToken: "refresh-beta",
            idToken: "id-beta"
        )
        let gamma = CodexBarProviderAccount(
            id: "acct_gamma",
            kind: .oauthTokens,
            label: "gamma@example.com",
            email: "gamma@example.com",
            openAIAccountId: "acct_gamma",
            accessToken: "access-gamma",
            refreshToken: "refresh-gamma",
            idToken: "id-gamma"
        )

        return CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: "acct_alpha"
            ),
            autoRouting: CodexBarAutoRoutingSettings(promptMode: .launchNewInstance),
            openAI: CodexBarOpenAISettings(
                accountOrder: accountOrder,
                accountOrderingMode: accountOrderingMode,
                manualActivationBehavior: .updateConfigOnly
            ),
            providers: [
                CodexBarProvider(
                    id: "openai-oauth",
                    kind: .openAIOAuth,
                    label: "OpenAI",
                    activeAccountId: "acct_alpha",
                    accounts: [alpha, beta, gamma]
                )
            ]
        )
    }

    private func makeAccount(email: String, accountId: String) -> TokenAccount {
        TokenAccount(
            email: email,
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)"
        )
    }
}

@MainActor
private final class TestSettingsSaveSink: SettingsSaveRequestApplying {
    private(set) var config: CodexBarConfig
    private(set) var appliedRequests: [SettingsSaveRequests] = []

    init(config: CodexBarConfig) {
        self.config = config
    }

    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws {
        self.appliedRequests.append(requests)
        try SettingsSaveRequestApplier.apply(requests, to: &self.config)
    }
}

private struct FailingSettingsSaveSink: SettingsSaveRequestApplying {
    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws {
        throw TestSaveError.failed
    }

    private enum TestSaveError: LocalizedError {
        case failed

        var errorDescription: String? { "save failed" }
    }
}
