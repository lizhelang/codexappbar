import Foundation

struct OAuthAccountMutationResult {
    let account: TokenAccount
    let active: Bool
    let synchronized: Bool
}

struct OAuthAccountSummary: Codable, Equatable {
    let accountID: String
    let email: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case email
        case active
    }
}

struct CodexBarOAuthAccountService {
    private let configStore: CodexBarConfigStore
    private let syncService: CodexSyncService
    private let switchJournalStore: SwitchJournalStore

    init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        syncService: CodexSyncService = CodexSyncService(),
        switchJournalStore: SwitchJournalStore = SwitchJournalStore()
    ) {
        self.configStore = configStore
        self.syncService = syncService
        self.switchJournalStore = switchJournalStore
    }

    func listAccounts() throws -> [OAuthAccountSummary] {
        let config = try self.configStore.loadOrMigrate()
        return config.oauthTokenAccounts().map {
            OAuthAccountSummary(
                accountID: $0.accountId,
                email: $0.email,
                active: $0.isActive
            )
        }
    }

    func importAccount(_ account: TokenAccount, activate: Bool) throws -> OAuthAccountMutationResult {
        var config = try self.configStore.loadOrMigrate()
        let result = config.upsertOAuthAccount(account, activate: activate)

        try self.configStore.save(config)
        if result.syncCodex {
            try self.syncService.synchronize(config: config)
        }
        if activate {
            try self.switchJournalStore.appendActivation(
                providerID: config.active.providerId,
                accountID: config.active.accountId
            )
        }

        let stored = self.makeTokenAccount(from: result.storedAccount, config: config) ?? account
        return OAuthAccountMutationResult(
            account: stored,
            active: stored.isActive,
            synchronized: result.syncCodex
        )
    }

    func activateAccount(accountID: String) throws -> OAuthAccountMutationResult {
        var config = try self.configStore.loadOrMigrate()
        let stored = try config.activateOAuthAccount(accountID: accountID)

        try self.configStore.save(config)
        try self.syncService.synchronize(config: config)
        try self.switchJournalStore.appendActivation(
            providerID: config.active.providerId,
            accountID: config.active.accountId
        )

        guard let tokenAccount = self.makeTokenAccount(from: stored, config: config) else {
            throw TokenStoreError.accountNotFound
        }
        return OAuthAccountMutationResult(account: tokenAccount, active: true, synchronized: true)
    }

    private func makeTokenAccount(from stored: CodexBarProviderAccount, config: CodexBarConfig) -> TokenAccount? {
        let provider = config.oauthProvider()
        let isActive = config.active.providerId == provider?.id && config.active.accountId == stored.id
        return stored.asTokenAccount(isActive: isActive)
    }
}
