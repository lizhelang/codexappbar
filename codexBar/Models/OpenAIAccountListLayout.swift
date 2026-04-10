import Foundation

enum OpenAIAccountSortBucket: Int {
    case usable
    case unavailableNonExhausted
    case exhausted
}

private enum OpenAIAccountDisplayPriority: Int {
    case prioritized
    case standard
}

struct OpenAIAccountGroup: Identifiable {
    let email: String
    let accounts: [TokenAccount]

    var id: String { email }
}

extension OpenAIAccountGroup {
    nonisolated var representativeAccount: TokenAccount? {
        accounts.first
    }

    nonisolated func headerQuotaRemark(now: Date = Date()) -> String? {
        representativeAccount?.headerQuotaRemark(now: now)
    }
}

enum OpenAIAccountListLayout {
    static let visibleGroupLimit = 4

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = [],
        highlightActiveAccount: Bool = true
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: [],
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder,
            highlightActiveAccount: highlightActiveAccount
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAILiveSessionAttribution,
        now: Date = Date(),
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = [],
        highlightActiveAccount: Bool = true
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.liveSummary(now: now).inUseSessionCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder,
            highlightActiveAccount: highlightActiveAccount
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAIRunningThreadAttribution,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = [],
        highlightActiveAccount: Bool = true
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.summary.runningThreadCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder,
            highlightActiveAccount: highlightActiveAccount
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        summary: OpenAIRunningThreadAttribution.Summary,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = [],
        highlightActiveAccount: Bool = true
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(summary.runningThreadCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder,
            highlightActiveAccount: highlightActiveAccount
        )
    }

    nonisolated private static func groupedAccounts(
        from accounts: [TokenAccount],
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        preferredAccountOrder: [String],
        highlightActiveAccount: Bool
    ) -> [OpenAIAccountGroup] {
        let preferredRanks = self.preferredAccountRanks(from: preferredAccountOrder)
        return Dictionary(grouping: accounts, by: \.email)
            .map { email, groupedAccounts in
                OpenAIAccountGroup(
                    email: email,
                    accounts: groupedAccounts.sorted {
                        self.displayAccountPrecedes(
                            $0,
                            $1,
                            prioritizedAccountIDs: prioritizedAccountIDs,
                            quotaSortSettings: quotaSortSettings,
                            preferredRanks: preferredRanks,
                            highlightActiveAccount: highlightActiveAccount
                        )
                    }
                )
            }
            .sorted {
                self.displayGroupPrecedes(
                    $0,
                    $1,
                    prioritizedAccountIDs: prioritizedAccountIDs,
                    quotaSortSettings: quotaSortSettings,
                    preferredRanks: preferredRanks,
                    highlightActiveAccount: highlightActiveAccount
                )
            }
    }

    nonisolated static func visibleGroups(
        from groups: [OpenAIAccountGroup],
        maxAccounts: Int
    ) -> [OpenAIAccountGroup] {
        guard maxAccounts > 0 else { return [] }

        var remaining = maxAccounts
        var visible: [OpenAIAccountGroup] = []

        for group in groups where remaining > 0 {
            let accounts = Array(group.accounts.prefix(remaining))
            guard accounts.isEmpty == false else { continue }
            visible.append(OpenAIAccountGroup(email: group.email, accounts: accounts))
            remaining -= accounts.count
        }

        return visible
    }

    nonisolated static func accountPrecedes(
        _ lhs: TokenAccount,
        _ rhs: TokenAccount,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init()
    ) -> Bool {
        if lhs.sortBucket != rhs.sortBucket {
            return lhs.sortBucket.rawValue < rhs.sortBucket.rawValue
        }

        let lhsWeightedPrimary = lhs.weightedPrimaryRemainingPercent(using: quotaSortSettings)
        let rhsWeightedPrimary = rhs.weightedPrimaryRemainingPercent(using: quotaSortSettings)
        if lhsWeightedPrimary != rhsWeightedPrimary {
            return lhsWeightedPrimary > rhsWeightedPrimary
        }

        let lhsWeightedSecondary = lhs.weightedSecondaryRemainingPercent(using: quotaSortSettings)
        let rhsWeightedSecondary = rhs.weightedSecondaryRemainingPercent(using: quotaSortSettings)
        if lhsWeightedSecondary != rhsWeightedSecondary {
            return lhsWeightedSecondary > rhsWeightedSecondary
        }

        let lhsPlanMultiplier = lhs.planQuotaMultiplier(using: quotaSortSettings)
        let rhsPlanMultiplier = rhs.planQuotaMultiplier(using: quotaSortSettings)
        if lhsPlanMultiplier != rhsPlanMultiplier {
            return lhsPlanMultiplier > rhsPlanMultiplier
        }

        if lhs.primaryRemainingPercent != rhs.primaryRemainingPercent {
            return lhs.primaryRemainingPercent > rhs.primaryRemainingPercent
        }

        if lhs.secondaryRemainingPercent != rhs.secondaryRemainingPercent {
            return lhs.secondaryRemainingPercent > rhs.secondaryRemainingPercent
        }

        let lhsEmail = lhs.email.localizedLowercase
        let rhsEmail = rhs.email.localizedLowercase
        if lhsEmail != rhsEmail {
            return lhsEmail < rhsEmail
        }

        return lhs.accountId < rhs.accountId
    }

    nonisolated private static func displayAccountPrecedes(
        _ lhs: TokenAccount,
        _ rhs: TokenAccount,
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        preferredRanks: [String: Int],
        highlightActiveAccount: Bool
    ) -> Bool {
        let lhsPriority = self.displayPriority(
            for: lhs,
            prioritizedAccountIDs: prioritizedAccountIDs,
            highlightActiveAccount: highlightActiveAccount
        )
        let rhsPriority = self.displayPriority(
            for: rhs,
            prioritizedAccountIDs: prioritizedAccountIDs,
            highlightActiveAccount: highlightActiveAccount
        )
        if lhsPriority != rhsPriority {
            return lhsPriority.rawValue < rhsPriority.rawValue
        }

        if let preferredOrderResult = self.preferredOrderPrecedes(
            lhs,
            rhs,
            preferredRanks: preferredRanks
        ) {
            return preferredOrderResult
        }

        return self.accountPrecedes(
            lhs,
            rhs,
            quotaSortSettings: quotaSortSettings
        )
    }

    nonisolated private static func displayPriority(
        for account: TokenAccount,
        prioritizedAccountIDs: Set<String>,
        highlightActiveAccount: Bool
    ) -> OpenAIAccountDisplayPriority {
        if (highlightActiveAccount && account.isActive) || prioritizedAccountIDs.contains(account.accountId) {
            return .prioritized
        }
        return .standard
    }

    nonisolated private static func displayGroupPrecedes(
        _ lhs: OpenAIAccountGroup,
        _ rhs: OpenAIAccountGroup,
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        preferredRanks: [String: Int],
        highlightActiveAccount: Bool
    ) -> Bool {
        let lhsRepresentative = lhs.accounts.first
        let rhsRepresentative = rhs.accounts.first

        switch (lhsRepresentative, rhsRepresentative) {
        case let (lhsAccount?, rhsAccount?):
            if self.displayAccountPrecedes(
                lhsAccount,
                rhsAccount,
                prioritizedAccountIDs: prioritizedAccountIDs,
                quotaSortSettings: quotaSortSettings,
                preferredRanks: preferredRanks,
                highlightActiveAccount: highlightActiveAccount
            ) {
                return true
            }
            if self.displayAccountPrecedes(
                rhsAccount,
                lhsAccount,
                prioritizedAccountIDs: prioritizedAccountIDs,
                quotaSortSettings: quotaSortSettings,
                preferredRanks: preferredRanks,
                highlightActiveAccount: highlightActiveAccount
            ) {
                return false
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        return lhs.email.localizedLowercase < rhs.email.localizedLowercase
    }

    nonisolated private static func preferredAccountRanks(from preferredAccountOrder: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: preferredAccountOrder.enumerated().map { ($0.element, $0.offset) })
    }

    nonisolated private static func preferredOrderPrecedes(
        _ lhs: TokenAccount,
        _ rhs: TokenAccount,
        preferredRanks: [String: Int]
    ) -> Bool? {
        // Approved base-order semantics:
        // 1. Compare only inside the same display band; active/running still float above.
        // 2. Manually listed accounts outrank unlisted accounts.
        // 3. Unlisted accounts fall back to the existing quota comparator.
        let lhsRank = preferredRanks[lhs.accountId]
        let rhsRank = preferredRanks[rhs.accountId]

        switch (lhsRank, rhsRank) {
        case let (lhsRank?, rhsRank?) where lhsRank != rhsRank:
            return lhsRank < rhsRank
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return nil
        }
    }
}
