import Foundation
import XCTest

final class AutoRoutingCoordinatorTests: CodexBarTestCase {
    func testConfigDecodesMissingDesktopAndPromptModeWithDefaults() throws {
        let json = """
        {
          "version": 1,
          "global": {
            "defaultModel": "gpt-5.4",
            "reviewModel": "gpt-5.4",
            "reasoningEffort": "xhigh"
          },
          "active": {},
          "providers": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        XCTAssertFalse(config.autoRouting.enabled)
        XCTAssertEqual(config.autoRouting.urgentThresholdPercent, 5)
        XCTAssertEqual(config.autoRouting.switchThresholdPercent, 10)
        XCTAssertNil(config.desktop.preferredCodexAppPath)
        XCTAssertEqual(config.autoRouting.promptMode, .launchNewInstance)
        XCTAssertEqual(config.openAI.popupAlertThresholdPercent, 20)
        XCTAssertEqual(config.openAI.usageDisplayMode, .used)
        XCTAssertEqual(config.openAI.quotaSort.plusRelativeWeight, 10)
        XCTAssertEqual(config.openAI.quotaSort.teamRelativeToPlusMultiplier, 1.5)
        XCTAssertEqual(config.openAI.accountOrder, [])
        XCTAssertEqual(config.openAI.accountOrderingMode, .quotaSort)
        XCTAssertEqual(config.openAI.manualActivationBehavior, .updateConfigOnly)
    }

    func testConfigDecodesLegacyNestedSectionsWithoutNewFields() throws {
        let json = """
        {
          "version": 1,
          "global": {
            "defaultModel": "gpt-5.4",
            "reviewModel": "gpt-5.4",
            "reasoningEffort": "xhigh"
          },
          "active": {},
          "autoRouting": {
            "enabled": true,
            "switchThresholdPercent": 15
          },
          "openAI": {
            "accountOrder": ["acct_a"],
            "popupAlertThresholdPercent": 25
          },
          "desktop": {},
          "providers": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        XCTAssertTrue(config.autoRouting.enabled)
        XCTAssertEqual(config.autoRouting.switchThresholdPercent, 15)
        XCTAssertEqual(config.autoRouting.promptMode, .launchNewInstance)
        XCTAssertEqual(config.openAI.accountOrder, ["acct_a"])
        XCTAssertEqual(config.openAI.popupAlertThresholdPercent, 25)
        XCTAssertEqual(config.openAI.usageDisplayMode, .used)
        XCTAssertEqual(config.openAI.quotaSort.plusRelativeWeight, 10)
        XCTAssertEqual(config.openAI.quotaSort.teamRelativeToPlusMultiplier, 1.5)
        XCTAssertEqual(config.openAI.accountOrderingMode, .quotaSort)
        XCTAssertEqual(config.openAI.manualActivationBehavior, .updateConfigOnly)
        XCTAssertNil(config.desktop.preferredCodexAppPath)
    }

    func testPreferredDisplayAccountOrderOnlyAppliesInManualMode() {
        var settings = CodexBarOpenAISettings(
            accountOrder: ["acct_b", "acct_a"],
            accountOrderingMode: .quotaSort
        )

        XCTAssertEqual(settings.preferredDisplayAccountOrder, [])

        settings.accountOrderingMode = .manual
        XCTAssertEqual(settings.preferredDisplayAccountOrder, ["acct_b", "acct_a"])
    }

    @MainActor
    func testSaveDesktopSettingsRejectsInvalidCodexAppPath() throws {
        let invalidURL = try self.makeDirectory(named: "Invalid/Codex.app")
        TokenStore.shared.load()

        XCTAssertThrowsError(
            try TokenStore.shared.saveDesktopSettings(
                DesktopSettingsUpdate(preferredCodexAppPath: invalidURL.path)
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                TokenStoreError.invalidCodexAppPath.localizedDescription
            )
        }
    }

    func testBestCandidatePrefersUsableAccountWithMostPrimaryQuota() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let low = self.makeAccount(accountId: "acct_low", primaryUsedPercent: 60, secondaryUsedPercent: 10)
        let high = self.makeAccount(accountId: "acct_high", primaryUsedPercent: 20, secondaryUsedPercent: 90)
        let exhausted = self.makeAccount(accountId: "acct_exhausted", primaryUsedPercent: 100, secondaryUsedPercent: 0)

        let best = AutoRoutingPolicy.bestCandidate(from: [low, exhausted, high], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_high")
    }

    func testBestCandidatePrefersWeightedPlusOverFreeWhenQuotaValueTies() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let free = self.makeAccount(
            accountId: "acct_free",
            planType: "free",
            primaryUsedPercent: 0,
            secondaryUsedPercent: 0
        )
        let plus = self.makeAccount(
            accountId: "acct_plus",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let best = AutoRoutingPolicy.bestCandidate(from: [free, plus], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_plus")
    }

    func testBestCandidateTreatsUnknownPlanTypeAsFree() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let unknown = self.makeAccount(
            accountId: "acct_unknown",
            planType: "enterprise",
            primaryUsedPercent: 0,
            secondaryUsedPercent: 0
        )
        let plus = self.makeAccount(
            accountId: "acct_plus",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let best = AutoRoutingPolicy.bestCandidate(from: [unknown, plus], settings: settings)

        XCTAssertEqual(unknown.planQuotaMultiplier, 1.0)
        XCTAssertEqual(best?.accountId, "acct_plus")
    }

    func testBestCandidateRespectsPinnedUsableAccount() {
        let settings = CodexBarAutoRoutingSettings(enabled: true, pinnedAccountId: "acct_pinned")
        let pinned = self.makeAccount(accountId: "acct_pinned", primaryUsedPercent: 45, secondaryUsedPercent: 10)
        let healthier = self.makeAccount(accountId: "acct_healthier", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let best = AutoRoutingPolicy.bestCandidate(from: [healthier, pinned], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_pinned")
    }

    func testAccountIsMarkedDegradedAtEightyPercent() {
        XCTAssertTrue(
            self.makeAccount(accountId: "acct_degraded", primaryUsedPercent: 80, secondaryUsedPercent: 10)
                .isDegradedForNextUseRouting
        )
        XCTAssertFalse(
            self.makeAccount(accountId: "acct_healthy", primaryUsedPercent: 79, secondaryUsedPercent: 10)
                .isDegradedForNextUseRouting
        )
    }

    func testDecisionKeepsHealthyCurrentNextUseAccount() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(accountId: "acct_current", primaryUsedPercent: 70, secondaryUsedPercent: 20)
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertNil(decision)
    }

    func testDecisionPromotesHealthierCandidateWhenCurrentIsDegraded() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(accountId: "acct_current", primaryUsedPercent: 80, secondaryUsedPercent: 20)
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertEqual(decision?.account.accountId, "acct_better")
        XCTAssertEqual(decision?.reason, .autoThreshold)
    }

    func testDecisionUsesPopupAlertThresholdForRecommendation() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(accountId: "acct_current", primaryUsedPercent: 70, secondaryUsedPercent: 10)
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let relaxed = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount,
            popupAlertThresholdPercent: 20
        )
        let strict = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount,
            popupAlertThresholdPercent: 30
        )

        XCTAssertNil(relaxed)
        XCTAssertEqual(strict?.account.accountId, "acct_better")
        XCTAssertEqual(strict?.reason, .autoThreshold)
    }

    func testThresholdPlanUsesLaunchNewInstanceMode() {
        let decision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoThreshold
        )

        let plan = AutoRoutingDecisionPlanner.plan(
            decision: decision,
            promptMode: .launchNewInstance,
            currentAccountID: "acct_current",
            suppressedPromptKey: nil
        )

        guard case let .thresholdPrompt(mode, promptKey, plannedDecision) = plan else {
            return XCTFail("Expected threshold prompt plan")
        }
        XCTAssertEqual(plannedDecision.account.accountId, decision.account.accountId)
        XCTAssertEqual(plannedDecision.reason, decision.reason)
        XCTAssertEqual(promptKey, "acct_current->acct_target:auto-threshold")
        XCTAssertEqual(mode, .launchNewInstance)
    }

    func testThresholdPlanUsesRemindOnlyMode() {
        let decision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoThreshold
        )

        let plan = AutoRoutingDecisionPlanner.plan(
            decision: decision,
            promptMode: .remindOnly,
            currentAccountID: "acct_current",
            suppressedPromptKey: nil
        )

        guard case let .thresholdPrompt(mode, promptKey, plannedDecision) = plan else {
            return XCTFail("Expected threshold prompt plan")
        }
        XCTAssertEqual(plannedDecision.account.accountId, decision.account.accountId)
        XCTAssertEqual(plannedDecision.reason, decision.reason)
        XCTAssertEqual(promptKey, "acct_current->acct_target:auto-threshold")
        XCTAssertEqual(mode, .remindOnly)
    }

    func testThresholdPlanIsDisabledOnlyForAutoThreshold() {
        let decision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoThreshold
        )

        let plan = AutoRoutingDecisionPlanner.plan(
            decision: decision,
            promptMode: .disabled,
            currentAccountID: "acct_current",
            suppressedPromptKey: nil
        )

        guard case let .none(clearSuppressedPrompt) = plan else {
            return XCTFail("Expected no prompt plan")
        }
        XCTAssertFalse(clearSuppressedPrompt)
    }

    func testForcedFailoverIgnoresDisabledPromptMode() {
        let decision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoExhausted
        )

        let plan = AutoRoutingDecisionPlanner.plan(
            decision: decision,
            promptMode: .disabled,
            currentAccountID: "acct_current",
            suppressedPromptKey: "acct_current->acct_target:auto-exhausted"
        )

        guard case let .forcedFailover(plannedDecision) = plan else {
            return XCTFail("Expected forced failover plan")
        }
        XCTAssertEqual(plannedDecision.account.accountId, decision.account.accountId)
        XCTAssertEqual(plannedDecision.reason, decision.reason)
    }

    func testRemindOnlySuppressionKeySuppressesSameDecisionButAllowsChangedDecision() {
        let decision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target_a", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoThreshold
        )
        let suppressedKey = AutoRoutingDecisionPlanner.promptKey(
            currentAccountID: "acct_current",
            decision: decision
        )

        let suppressedPlan = AutoRoutingDecisionPlanner.plan(
            decision: decision,
            promptMode: .remindOnly,
            currentAccountID: "acct_current",
            suppressedPromptKey: suppressedKey
        )
        guard case .suppressed = suppressedPlan else {
            return XCTFail("Expected suppressed plan")
        }

        let changedTargetDecision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target_b", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoThreshold
        )
        let changedTargetPlan = AutoRoutingDecisionPlanner.plan(
            decision: changedTargetDecision,
            promptMode: .remindOnly,
            currentAccountID: "acct_current",
            suppressedPromptKey: suppressedKey
        )
        guard case let .thresholdPrompt(mode, promptKey, plannedDecision) = changedTargetPlan else {
            return XCTFail("Expected prompt for changed target")
        }
        XCTAssertEqual(plannedDecision.account.accountId, changedTargetDecision.account.accountId)
        XCTAssertEqual(plannedDecision.reason, changedTargetDecision.reason)
        XCTAssertEqual(promptKey, "acct_current->acct_target_b:auto-threshold")
        XCTAssertEqual(mode, .remindOnly)

        let changedReasonDecision = AutoRoutingPolicy.Decision(
            account: self.makeAccount(accountId: "acct_target_a", primaryUsedPercent: 10, secondaryUsedPercent: 5),
            reason: .autoUnavailable
        )
        let changedReasonPlan = AutoRoutingDecisionPlanner.plan(
            decision: changedReasonDecision,
            promptMode: .remindOnly,
            currentAccountID: "acct_current",
            suppressedPromptKey: suppressedKey
        )
        guard case let .forcedFailover(plannedDecision) = changedReasonPlan else {
            return XCTFail("Expected forced failover plan for changed reason")
        }
        XCTAssertEqual(plannedDecision.account.accountId, changedReasonDecision.account.accountId)
        XCTAssertEqual(plannedDecision.reason, changedReasonDecision.reason)
    }

    func testDecisionPromotesMixedPlanCandidateWhenCurrentIsDegraded() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(
            accountId: "acct_current",
            planType: "free",
            primaryUsedPercent: 80,
            secondaryUsedPercent: 0
        )
        let better = self.makeAccount(
            accountId: "acct_better",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertEqual(decision?.account.accountId, "acct_better")
        XCTAssertEqual(decision?.reason, .autoThreshold)
    }

    func testHardFailoverReasonUsesUnavailableBeforeExhausted() {
        let unavailable = self.makeAccount(
            accountId: "acct_unavailable",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 100,
            tokenExpired: true
        )
        let exhausted = self.makeAccount(accountId: "acct_exhausted", primaryUsedPercent: 100, secondaryUsedPercent: 0)

        XCTAssertEqual(AutoRoutingPolicy.hardFailoverReason(for: unavailable), .autoUnavailable)
        XCTAssertEqual(AutoRoutingPolicy.hardFailoverReason(for: exhausted), .autoExhausted)
    }

    func testBestCandidateExcludesUnavailableAndExhaustedAccounts() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let suspended = self.makeAccount(
            accountId: "acct_suspended",
            planType: "team",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10,
            isSuspended: true
        )
        let expired = self.makeAccount(
            accountId: "acct_expired",
            planType: "plus",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10,
            tokenExpired: true
        )
        let exhausted = self.makeAccount(
            accountId: "acct_exhausted",
            planType: "team",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 0
        )
        let healthy = self.makeAccount(accountId: "acct_healthy", primaryUsedPercent: 25, secondaryUsedPercent: 10)

        let best = AutoRoutingPolicy.bestCandidate(
            from: [suspended, expired, exhausted, healthy],
            settings: settings
        )

        XCTAssertEqual(best?.accountId, "acct_healthy")
    }

    func testUsageStatusThresholdsRemainUnchangedAcrossPlans() {
        XCTAssertEqual(
            self.makeAccount(accountId: "acct_ok_plus", planType: "plus", primaryUsedPercent: 79, secondaryUsedPercent: 0)
                .usageStatus,
            .ok
        )
        XCTAssertEqual(
            self.makeAccount(accountId: "acct_warning_team", planType: "team", primaryUsedPercent: 80, secondaryUsedPercent: 0)
                .usageStatus,
            .warning
        )
        XCTAssertEqual(
            self.makeAccount(accountId: "acct_exceeded_unknown", planType: "enterprise", primaryUsedPercent: 100, secondaryUsedPercent: 0)
                .usageStatus,
            .exceeded
        )
    }

    func testHandleAppLaunchDoesNotAutoSwitchWhenCurrentIsDegraded() async throws {
        let accounts = [
            self.makeAccount(accountId: "acct_active", primaryUsedPercent: 80, secondaryUsedPercent: 20),
            self.makeAccount(accountId: "acct_better", primaryUsedPercent: 15, secondaryUsedPercent: 10),
        ]
        try self.seedSharedStore(
            accounts: accounts,
            activeAccountID: "acct_active",
            autoRouting: CodexBarAutoRoutingSettings(enabled: true)
        )

        let coordinator = await MainActor.run {
            AutoRoutingCoordinator(store: TokenStore.shared, refreshAllAction: { _ in [] })
        }

        await MainActor.run {
            TokenStore.shared.load()
        }
        await coordinator.handleAppLaunch()

        let active = await MainActor.run { TokenStore.shared.activeAccount()?.accountId }
        XCTAssertEqual(active, "acct_active")
    }

    func testHandleAppLaunchDoesNotSwitchWhenDisabled() async throws {
        let accounts = [
            self.makeAccount(accountId: "acct_active", primaryUsedPercent: 70, secondaryUsedPercent: 20),
            self.makeAccount(accountId: "acct_better", primaryUsedPercent: 15, secondaryUsedPercent: 10),
        ]
        try self.seedSharedStore(
            accounts: accounts,
            activeAccountID: "acct_active",
            autoRouting: CodexBarAutoRoutingSettings(enabled: false)
        )

        let coordinator = await MainActor.run {
            AutoRoutingCoordinator(store: TokenStore.shared, refreshAllAction: { _ in [] })
        }

        let initialJournalCount = try self.switchJournalEntries().count
        await coordinator.handleAppLaunch()

        let active = await MainActor.run { TokenStore.shared.activeAccount()?.accountId }
        XCTAssertEqual(active, "acct_active")
        XCTAssertEqual(try self.switchJournalEntries().count, initialJournalCount)
    }

    func testHandleUsageSnapshotChangedKeepsHealthyCurrentAccount() async throws {
        let accounts = [
            self.makeAccount(accountId: "acct_active", primaryUsedPercent: 70, secondaryUsedPercent: 20),
            self.makeAccount(accountId: "acct_better", primaryUsedPercent: 15, secondaryUsedPercent: 10),
        ]
        try self.seedSharedStore(
            accounts: accounts,
            activeAccountID: "acct_active",
            autoRouting: CodexBarAutoRoutingSettings(enabled: true)
        )

        let coordinator = await MainActor.run {
            AutoRoutingCoordinator(store: TokenStore.shared, refreshAllAction: { _ in [] })
        }

        let initialJournalCount = try self.switchJournalEntries().count
        await coordinator.handleUsageSnapshotChanged()

        let active = await MainActor.run { TokenStore.shared.activeAccount()?.accountId }
        XCTAssertEqual(active, "acct_active")
        XCTAssertEqual(try self.switchJournalEntries().count, initialJournalCount)
    }

    func testHandlePostActiveAccountRefreshDoesNotAutoFailOverWhenActiveBecomesUnavailable() async throws {
        let accounts = [
            self.makeAccount(accountId: "acct_active", primaryUsedPercent: 30, secondaryUsedPercent: 20, tokenExpired: true),
            self.makeAccount(accountId: "acct_fallback", primaryUsedPercent: 10, secondaryUsedPercent: 10),
        ]
        try self.seedSharedStore(
            accounts: accounts,
            activeAccountID: "acct_active",
            autoRouting: CodexBarAutoRoutingSettings(enabled: true)
        )

        let coordinator = await MainActor.run {
            AutoRoutingCoordinator(store: TokenStore.shared, refreshAllAction: { _ in [] })
        }

        await MainActor.run {
            TokenStore.shared.load()
        }
        await coordinator.handlePostActiveAccountRefresh(accountID: "acct_active")

        let active = await MainActor.run { TokenStore.shared.activeAccount()?.accountId }
        XCTAssertEqual(active, "acct_active")
    }

    func testHandleUsageSnapshotChangedIgnoresCustomProviderSelections() async throws {
        let oauthAccounts = [
            self.makeAccount(accountId: "acct_oauth_a", primaryUsedPercent: 80, secondaryUsedPercent: 20),
            self.makeAccount(accountId: "acct_oauth_b", primaryUsedPercent: 10, secondaryUsedPercent: 10),
        ]
        let oauthProvider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            activeAccountId: "acct_oauth_a",
            accounts: oauthAccounts.map {
                CodexBarProviderAccount.fromTokenAccount($0, existingID: $0.accountId)
            }
        )
        let compatibleProvider = CodexBarProvider(
            id: "custom-provider",
            kind: .openAICompatible,
            label: "Custom",
            enabled: true,
            baseURL: "https://example.com",
            activeAccountId: "custom-account",
            accounts: [
                CodexBarProviderAccount(
                    id: "custom-account",
                    kind: .apiKey,
                    label: "Default",
                    apiKey: "sk-test"
                )
            ]
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(),
            active: CodexBarActiveSelection(providerId: "custom-provider", accountId: "custom-account"),
            autoRouting: CodexBarAutoRoutingSettings(enabled: true),
            providers: [oauthProvider, compatibleProvider]
        )

        try CodexBarConfigStore().save(config)
        TokenStore.shared.load()

        let coordinator = await MainActor.run {
            AutoRoutingCoordinator(store: TokenStore.shared, refreshAllAction: { _ in [] })
        }

        let initialJournalCount = try self.switchJournalEntries().count
        await coordinator.handleUsageSnapshotChanged()

        let activeProviderKind = await MainActor.run { TokenStore.shared.activeProvider?.kind }
        XCTAssertEqual(activeProviderKind, .openAICompatible)
        XCTAssertEqual(try self.switchJournalEntries().count, initialJournalCount)
    }

    private func seedSharedStore(
        accounts: [TokenAccount],
        activeAccountID: String?,
        autoRouting: CodexBarAutoRoutingSettings
    ) throws {
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            activeAccountId: activeAccountID,
            accounts: accounts.map {
                CodexBarProviderAccount.fromTokenAccount($0, existingID: $0.accountId)
            }
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(),
            active: CodexBarActiveSelection(providerId: "openai-oauth", accountId: activeAccountID),
            autoRouting: autoRouting,
            providers: [provider]
        )

        try CodexBarConfigStore().save(config)
        TokenStore.shared.load()
    }

    private func switchJournalEntries() throws -> [String] {
        guard FileManager.default.fileExists(atPath: CodexPaths.switchJournalURL.path) else {
            return []
        }
        let content = try String(contentsOf: CodexPaths.switchJournalURL, encoding: .utf8)
        return content.split(separator: "\n").map(String.init)
    }

    private func makeDirectory(named relativePath: String) throws -> URL {
        let url = CodexPaths.realHome.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAccount(
        accountId: String,
        planType: String = "free",
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double,
        tokenExpired: Bool = false,
        isSuspended: Bool = false
    ) -> TokenAccount {
        TokenAccount(
            email: "\(accountId)@example.com",
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)",
            planType: planType,
            primaryUsedPercent: primaryUsedPercent,
            secondaryUsedPercent: secondaryUsedPercent,
            isActive: false,
            isSuspended: isSuspended,
            tokenExpired: tokenExpired
        )
    }
}
