import Combine
import Foundation

final class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published var accounts: [TokenAccount] = []
    @Published private(set) var config: CodexBarConfig
    @Published private(set) var localCostSummary: LocalCostSummary = .empty
    @Published private(set) var billingHistory: BillingHistory = .empty

    private let configStore = CodexBarConfigStore()
    private let syncService = CodexSyncService()
    private let costSummaryService = LocalCostSummaryService()
    private let billingHistoryService = BillingHistoryService()

    private init() {
        if let loaded = try? self.configStore.loadOrMigrate() {
            self.config = loaded
        } else {
            self.config = CodexBarConfig()
        }

        self.publishState()
        self.seedSwitchJournalIfNeeded()
        try? self.syncService.synchronize(config: self.config)
    }

    var customProviders: [CodexBarProvider] {
        self.config.providers.filter { $0.kind == .openAICompatible }
    }

    var activeProvider: CodexBarProvider? {
        self.config.activeProvider()
    }

    var activeProviderAccount: CodexBarProviderAccount? {
        self.config.activeAccount()
    }

    var activeModel: String {
        self.config.global.defaultModel
    }

    func load() {
        if let loaded = try? self.configStore.loadOrMigrate() {
            self.config = loaded
            self.publishState()
            self.refreshLocalCostSummary()
            self.refreshBillingHistory()
        }
    }

    func addOrUpdate(_ account: TokenAccount) {
        var provider = self.ensureOAuthProvider()
        if let index = provider.accounts.firstIndex(where: { $0.openAIAccountId == account.accountId }) {
            let existing = provider.accounts[index]
            var updated = CodexBarProviderAccount.fromTokenAccount(account, existingID: existing.id)
            updated.addedAt = existing.addedAt ?? Date()
            updated.label = existing.label
            provider.accounts[index] = updated
        } else {
            provider.accounts.append(CodexBarProviderAccount.fromTokenAccount(account, existingID: account.accountId))
            if provider.activeAccountId == nil {
                provider.activeAccountId = account.accountId
            }
        }

        self.upsertProvider(provider)

        let shouldSync = self.config.active.providerId == provider.id &&
            provider.accounts.contains(where: { $0.id == self.config.active.accountId })
        self.persistIgnoringErrors(syncCodex: shouldSync)
    }

    func remove(_ account: TokenAccount) {
        guard var provider = self.oauthProvider() else { return }
        provider.accounts.removeAll { $0.openAIAccountId == account.accountId }

        if provider.accounts.isEmpty {
            self.config.providers.removeAll { $0.id == provider.id }
            if self.config.active.providerId == provider.id {
                let fallback = self.config.providers.first
                self.config.active.providerId = fallback?.id
                self.config.active.accountId = fallback?.activeAccount?.id
            }
        } else {
            if provider.activeAccountId == account.accountId {
                provider.activeAccountId = provider.accounts.first?.id
            }
            if self.config.active.providerId == provider.id && self.config.active.accountId == account.accountId {
                self.config.active.accountId = provider.activeAccountId
            }
            self.upsertProvider(provider)
        }

        self.persistIgnoringErrors(syncCodex: self.config.active.providerId == provider.id)
    }

    func activate(_ account: TokenAccount) throws {
        guard var provider = self.oauthProvider(),
              let stored = provider.accounts.first(where: { $0.openAIAccountId == account.accountId }) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = stored.id
        self.upsertProvider(provider)
        self.config.active.providerId = provider.id
        self.config.active.accountId = stored.id

        try self.persist(syncCodex: true)
        try self.appendSwitchJournal()
    }

    func activeAccount() -> TokenAccount? {
        self.accounts.first(where: { $0.isActive })
    }

    func activateCustomProvider(providerID: String, accountID: String) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        guard provider.accounts.contains(where: { $0.id == accountID }) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = accountID
        self.upsertProvider(provider)
        self.config.active.providerId = provider.id
        self.config.active.accountId = accountID

        try self.persist(syncCodex: true)
        try self.appendSwitchJournal()
    }

    func addCustomProvider(label: String, baseURL: String, accountLabel: String, apiKey: String) throws {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountLabel = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLabel.isEmpty == false,
              trimmedBaseURL.isEmpty == false,
              trimmedAPIKey.isEmpty == false else {
            throw TokenStoreError.invalidInput
        }

        let providerID = self.slug(from: trimmedLabel)
        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: trimmedAccountLabel.isEmpty ? "Default" : trimmedAccountLabel,
            apiKey: trimmedAPIKey,
            addedAt: Date()
        )
        let provider = CodexBarProvider(
            id: providerID,
            kind: .openAICompatible,
            label: trimmedLabel,
            enabled: true,
            baseURL: trimmedBaseURL,
            activeAccountId: account.id,
            accounts: [account]
        )

        self.config.providers.removeAll { $0.id == provider.id }
        self.config.providers.append(provider)
        self.config.active.providerId = provider.id
        self.config.active.accountId = account.id

        try self.persist(syncCodex: true)
        try self.appendSwitchJournal()
    }

    func addCustomProviderAccount(providerID: String, label: String, apiKey: String) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false else { throw TokenStoreError.invalidInput }

        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Account \(provider.accounts.count + 1)" : label.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: trimmedAPIKey,
            addedAt: Date()
        )
        provider.accounts.append(account)
        if provider.activeAccountId == nil {
            provider.activeAccountId = account.id
        }
        self.upsertProvider(provider)
        try self.persist(syncCodex: false)
    }

    func removeCustomProviderAccount(providerID: String, accountID: String) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        provider.accounts.removeAll { $0.id == accountID }
        if provider.accounts.isEmpty {
            self.config.providers.removeAll { $0.id == providerID }
            if self.config.active.providerId == providerID {
                let fallback = self.config.providers.first
                self.config.active.providerId = fallback?.id
                self.config.active.accountId = fallback?.activeAccount?.id
                try self.persist(syncCodex: fallback != nil)
                return
            }
        } else {
            if provider.activeAccountId == accountID {
                provider.activeAccountId = provider.accounts.first?.id
            }
            if self.config.active.providerId == providerID && self.config.active.accountId == accountID {
                self.upsertProvider(provider)
                self.config.active.accountId = provider.activeAccountId
                try self.persist(syncCodex: true)
                return
            }
            self.upsertProvider(provider)
        }
        try self.persist(syncCodex: false)
    }

    func removeCustomProvider(providerID: String) throws {
        self.config.providers.removeAll { $0.id == providerID }
        if self.config.active.providerId == providerID {
            let fallback = self.oauthProvider() ?? self.customProviders.first
            self.config.active.providerId = fallback?.id
            self.config.active.accountId = fallback?.activeAccount?.id
            try self.persist(syncCodex: fallback != nil)
            return
        }
        try self.persist(syncCodex: false)
    }

    func markActiveAccount() {
        self.publishState()
    }

    // MARK: - Private

    private func oauthProvider() -> CodexBarProvider? {
        self.config.providers.first(where: { $0.kind == .openAIOAuth })
    }

    private func ensureOAuthProvider() -> CodexBarProvider {
        if let provider = self.oauthProvider() {
            return provider
        }
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            baseURL: nil
        )
        self.config.providers.append(provider)
        return provider
    }

    private func upsertProvider(_ provider: CodexBarProvider) {
        if let index = self.config.providers.firstIndex(where: { $0.id == provider.id }) {
            self.config.providers[index] = provider
        } else {
            self.config.providers.append(provider)
        }
    }

    private func persist(syncCodex: Bool) throws {
        try self.configStore.save(self.config)
        if syncCodex {
            try self.syncService.synchronize(config: self.config)
        }
        self.publishState()
    }

    private func persistIgnoringErrors(syncCodex: Bool) {
        do {
            try self.persist(syncCodex: syncCodex)
        } catch {
            self.publishState()
        }
    }

    private func publishState() {
        guard let provider = self.oauthProvider() else {
            self.accounts = []
            return
        }

        let isOAuthActive = self.config.active.providerId == provider.id
        self.accounts = provider.accounts.compactMap { stored in
            stored.asTokenAccount(isActive: isOAuthActive && self.config.active.accountId == stored.id)
        }.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.email < rhs.email
        }
    }

    func refreshLocalCostSummary() {
        let service = self.costSummaryService
        DispatchQueue.global(qos: .utility).async {
            let summary = service.load()
            DispatchQueue.main.async {
                self.localCostSummary = summary
            }
        }
    }

    func refreshBillingHistory() {
        let service = self.billingHistoryService
        let config = self.config
        DispatchQueue.global(qos: .utility).async {
            let history = service.load(config: config)
            DispatchQueue.main.async {
                self.billingHistory = history
            }
        }
    }

    private func appendSwitchJournal() throws {
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "providerId": self.config.active.providerId as Any,
            "accountId": self.config.active.accountId as Any,
            "type": "activation",
        ]
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"

        let fileManager = FileManager.default
        try CodexPaths.ensureDirectories()
        if fileManager.fileExists(atPath: CodexPaths.switchJournalURL.path) == false {
            try CodexPaths.writeSecureFile(Data(line.utf8), to: CodexPaths.switchJournalURL)
            return
        }
        let handle = try FileHandle(forWritingTo: CodexPaths.switchJournalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    private func seedSwitchJournalIfNeeded() {
        guard FileManager.default.fileExists(atPath: CodexPaths.switchJournalURL.path) == false,
              self.config.active.providerId != nil else { return }
        try? self.appendSwitchJournal()
    }

    private func slug(from label: String) -> String {
        let lowered = label.lowercased()
        let slug = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "provider-\(UUID().uuidString.lowercased())" : slug
    }
}

enum TokenStoreError: LocalizedError {
    case accountNotFound
    case providerNotFound
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .accountNotFound: return "未找到账号"
        case .providerNotFound: return "未找到 provider"
        case .invalidInput: return "输入无效"
        }
    }
}
