import AppKit
import Combine
import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @EnvironmentObject var store: TokenStore
    @EnvironmentObject var oauth: OAuthManager

    @State private var isRefreshing = false
    @State private var showError: String?
    @State private var showSuccess: String?
    @State private var now = Date()
    @State private var refreshingAccounts: Set<String> = []
    @State private var menuVisible = false
    @State private var languageToggle = false
    @State private var isCostSummaryHovered = false
    @State private var isCostPanelHovered = false
    @State private var isCostPanelPresented = false
    @State private var pendingCostHide: DispatchWorkItem?

    private let countdownTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let quickTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let slowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var groupedAccounts: [(email: String, accounts: [TokenAccount])] {
        var dict: [String: [TokenAccount]] = [:]
        var order: [String] = []
        for acc in store.accounts {
            if dict[acc.email] == nil {
                dict[acc.email] = []
                order.append(acc.email)
            }
            dict[acc.email]!.append(acc)
        }
        let sortedOrder = order.sorted { e1, e2 in
            let best1 = bestStatus(dict[e1]!)
            let best2 = bestStatus(dict[e2]!)
            return best1 < best2
        }
        return sortedOrder.map { email in
            let sorted = dict[email]!.sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                return statusRank(a) < statusRank(b)
            }
            return (email: email, accounts: sorted)
        }
    }

    private func bestStatus(_ accounts: [TokenAccount]) -> Int {
        accounts.map { statusRank($0) }.min() ?? 2
    }

    private func statusRank(_ a: TokenAccount) -> Int {
        switch a.usageStatus {
        case .ok: return 0
        case .warning: return 1
        case .exceeded: return 2
        case .banned: return 3
        }
    }

    private var availableCount: Int {
        store.accounts.filter { $0.usageStatus == .ok }.count
    }

    private var isCompletelyEmpty: Bool {
        store.accounts.isEmpty && store.customProviders.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            mainMenuContent

            if isCostPanelPresented {
                CostDetailsPanelView(
                    summary: store.localCostSummary,
                    currency: currency,
                    compactTokens: compactTokens,
                    shortDay: shortDay
                )
                .onHover { hovering in
                    setCostPanelHover(hovering)
                }
                .transition(.opacity)
            }
        }
        .frame(width: isCostPanelPresented ? 582 : 300)
        .animation(.easeInOut(duration: 0.16), value: isCostPanelPresented)
        .onReceive(countdownTimer) { _ in now = Date() }
        .onReceive(quickTimer) { _ in
            guard menuVisible,
                  let active = store.accounts.first(where: { $0.isActive }),
                  !active.secondaryExhausted else { return }
            Task {
                await refreshAccount(active)
                store.markActiveAccount()
                autoSwitchIfNeeded()
            }
        }
        .onReceive(slowTimer) { _ in
            Task {
                if !menuVisible { await refresh() }
                store.markActiveAccount()
                if menuVisible {
                    store.refreshLocalCostSummary()
                    store.refreshBillingHistory()
                }
                autoSwitchIfNeeded()
            }
        }
        .onAppear {
            menuVisible = true
            store.markActiveAccount()
            store.refreshLocalCostSummary()
            store.refreshBillingHistory()
        }
        .onDisappear {
            menuVisible = false
            pendingCostHide?.cancel()
            pendingCostHide = nil
            isCostPanelPresented = false
            isCostSummaryHovered = false
            isCostPanelHovered = false
        }
    }

    @ViewBuilder
    private var mainMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CodexAppBar")
                    .font(.system(size: 13, weight: .semibold))

                if let active = store.activeProvider {
                    Text(active.label)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }

                if !store.accounts.isEmpty {
                    Text(L.available(availableCount, store.accounts.count))
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(availableCount > 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .foregroundColor(availableCount > 0 ? .green : .red)
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .help(L.refreshUsage)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let activeProvider = store.activeProvider,
               let activeAccount = store.activeProviderAccount {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(activeProvider.label) · \(activeAccount.label)")
                        .font(.system(size: 11, weight: .medium))
                    Text("Model: \(store.activeModel)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Changes apply to new sessions.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            if isCompletelyEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(L.noAccounts)
                        .foregroundColor(.secondary)
                    Text("Add an OpenAI account or create a custom provider.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !store.customProviders.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Providers")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)

                                ForEach(store.customProviders) { provider in
                                    CompatibleProviderRowView(
                                        provider: provider,
                                        isActiveProvider: store.activeProvider?.id == provider.id,
                                        activeAccountId: provider.activeAccountId
                                    ) { account in
                                        activateCompatibleProvider(providerID: provider.id, accountID: account.id)
                                    } onAddAccount: {
                                        openAddProviderAccountWindow(provider: provider)
                                    } onDeleteAccount: { account in
                                        deleteCompatibleAccount(providerID: provider.id, accountID: account.id)
                                    } onDeleteProvider: {
                                        deleteProvider(providerID: provider.id)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("OpenAI Accounts")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)

                                Spacer()

                                Button("Login OpenAI") {
                                    startOAuthLogin()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                .font(.system(size: 10, weight: .medium))
                            }

                            if store.accounts.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No OpenAI account added.")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Login to track quota and switch OpenAI OAuth accounts.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.06))
                                )
                            } else {
                                ForEach(groupedAccounts, id: \.email) { group in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.email)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .padding(.leading, 4)

                                        ForEach(group.accounts) { account in
                                            AccountRowView(
                                                account: account,
                                                isActive: account.isActive,
                                                now: now,
                                                isRefreshing: refreshingAccounts.contains(account.id)
                                            ) {
                                                activateAccount(account)
                                            } onRefresh: {
                                                Task { await refreshAccount(account) }
                                            } onReauth: {
                                                reauthAccount(account)
                                            } onDelete: {
                                                store.remove(account)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        CostSummaryRowView(
                            summary: store.localCostSummary,
                            currency: currency,
                            compactTokens: compactTokens
                        )
                        .onHover { hovering in
                            setCostSummaryHover(hovering)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(minHeight: 180, maxHeight: 420)
            }

            if let success = showSuccess {
                Divider()
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if let error = showError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        showError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            HStack(spacing: 8) {
                if let lastUpdate = store.accounts.compactMap({ $0.lastChecked }).max() {
                    Text(relativeTime(lastUpdate))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else if let provider = store.activeProvider {
                    Text(provider.hostLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    startOAuthLogin()
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L.addAccount)

                Button {
                    openAddProviderWindow()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Add Provider")

                Button {
                    switch L.languageOverride {
                    case nil: L.languageOverride = true
                    case true: L.languageOverride = false
                    case false: L.languageOverride = nil
                    }
                    languageToggle.toggle()
                } label: {
                    let label = languageToggle ? L.languageOverride : L.languageOverride
                    Text(label == nil ? "AUTO" : (label == true ? "中" : "EN"))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("切换语言 / Switch Language")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L.quit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return L.justUpdated }
        if seconds < 3600 { return L.minutesAgo(seconds / 60) }
        return L.hoursAgo(seconds / 3600)
    }

    private func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func compactTokens(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000_000 {
            return String(format: "%.2fB", number / 1_000_000_000)
        }
        if number >= 1_000_000 {
            return String(format: "%.2fM", number / 1_000_000)
        }
        if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return "\(value)"
    }

    private func setCostSummaryHover(_ hovering: Bool) {
        isCostSummaryHovered = hovering
        if hovering {
            presentCostPanel()
        } else {
            scheduleCostPanelHideIfNeeded()
        }
    }

    private func setCostPanelHover(_ hovering: Bool) {
        isCostPanelHovered = hovering
        if hovering {
            presentCostPanel()
        } else {
            scheduleCostPanelHideIfNeeded()
        }
    }

    private func presentCostPanel() {
        pendingCostHide?.cancel()
        pendingCostHide = nil
        isCostPanelPresented = true
    }

    private func scheduleCostPanelHideIfNeeded() {
        pendingCostHide?.cancel()
        let work = DispatchWorkItem {
            if !isCostSummaryHovered && !isCostPanelHovered {
                isCostPanelPresented = false
            }
        }
        pendingCostHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func activateAccount(_ account: TokenAccount) {
        do {
            try store.activate(account)
            showSuccess = "Updated Codex configuration. Changes apply to new sessions."
        } catch {
            showError = error.localizedDescription
        }
    }

    private func activateCompatibleProvider(providerID: String, accountID: String) {
        do {
            try store.activateCustomProvider(providerID: providerID, accountID: accountID)
            showSuccess = "Updated Codex configuration. Changes apply to new sessions."
        } catch {
            showError = error.localizedDescription
        }
    }

    private func deleteCompatibleAccount(providerID: String, accountID: String) {
        do {
            try store.removeCustomProviderAccount(providerID: providerID, accountID: accountID)
            showSuccess = "Removed provider account."
        } catch {
            showError = error.localizedDescription
        }
    }

    private func deleteProvider(providerID: String) {
        do {
            try store.removeCustomProvider(providerID: providerID)
            showSuccess = "Removed provider."
        } catch {
            showError = error.localizedDescription
        }
    }

    private func startOAuthLogin() {
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                let account = AccountBuilder.build(from: tokens)
                store.addOrUpdate(account)
                Task { await WhamService.shared.refreshOne(account: account, store: store) }
                showSuccess = "Updated Codex configuration. Changes apply to new sessions."
                DetachedWindowPresenter.shared.close(id: "oauth-login")
            case .failure(let error):
                showError = error.localizedDescription
            }
        }
        openOAuthWindow()
    }

    private func openOAuthWindow() {
        DetachedWindowPresenter.shared.show(
            id: "oauth-login",
            title: "OpenAI OAuth",
            size: CGSize(width: 560, height: 420)
        ) {
            OpenAIManualOAuthSheet(
                authURL: oauth.pendingAuthURL ?? "",
                isAuthenticating: oauth.isAuthenticating,
                errorMessage: oauth.errorMessage
            ) { input in
                oauth.completeOAuth(from: input)
            } onOpenBrowser: {
                if let authURL = oauth.pendingAuthURL, let url = URL(string: authURL) {
                    NSWorkspace.shared.open(url)
                }
            } onCopyLink: {
                guard let authURL = oauth.pendingAuthURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(authURL, forType: .string)
            } onCancel: {
                oauth.cancel()
                DetachedWindowPresenter.shared.close(id: "oauth-login")
            }
        }
    }

    private func openAddProviderWindow() {
        DetachedWindowPresenter.shared.show(
            id: "add-provider",
            title: "Add Provider",
            size: CGSize(width: 420, height: 320)
        ) {
            AddProviderSheet { label, baseURL, accountLabel, apiKey in
                do {
                    try store.addCustomProvider(label: label, baseURL: baseURL, accountLabel: accountLabel, apiKey: apiKey)
                    showSuccess = "Updated Codex configuration. Changes apply to new sessions."
                    DetachedWindowPresenter.shared.close(id: "add-provider")
                } catch {
                    showError = error.localizedDescription
                }
            } onCancel: {
                DetachedWindowPresenter.shared.close(id: "add-provider")
            }
        }
    }

    private func openAddProviderAccountWindow(provider: CodexBarProvider) {
        DetachedWindowPresenter.shared.show(
            id: "add-provider-account-\(provider.id)",
            title: "Add Account",
            size: CGSize(width: 400, height: 220)
        ) {
            AddProviderAccountSheet(provider: provider) { label, apiKey in
                do {
                    try store.addCustomProviderAccount(providerID: provider.id, label: label, apiKey: apiKey)
                    showSuccess = "Saved provider account."
                    DetachedWindowPresenter.shared.close(id: "add-provider-account-\(provider.id)")
                } catch {
                    showError = error.localizedDescription
                }
            } onCancel: {
                DetachedWindowPresenter.shared.close(id: "add-provider-account-\(provider.id)")
            }
        }
    }

    private func autoSwitchIfNeeded() {
        guard let active = store.accounts.first(where: { $0.isActive }) else { return }

        let primary5hRemaining = 100.0 - active.primaryUsedPercent
        let secondary7dRemaining = 100.0 - active.secondaryUsedPercent
        let shouldSwitch = primary5hRemaining <= 10.0 || secondary7dRemaining <= 3.0
        guard shouldSwitch else { return }

        let candidates = store.accounts.filter {
            !$0.isSuspended && !$0.tokenExpired && $0.accountId != active.accountId
        }.sorted {
            if statusRank($0) != statusRank($1) { return statusRank($0) < statusRank($1) }
            let rem0 = min(100 - $0.primaryUsedPercent, 100 - $0.secondaryUsedPercent)
            let rem1 = min(100 - $1.primaryUsedPercent, 100 - $1.secondaryUsedPercent)
            return rem0 > rem1
        }

        guard let best = candidates.first else {
            sendNotification(title: L.autoSwitchTitle, body: L.autoSwitchNoCandidates)
            return
        }

        do {
            try store.activate(best)
            sendAutoSwitchNotification(from: active, to: best)
        } catch {}
    }

    private func sendAutoSwitchNotification(from old: TokenAccount, to new: TokenAccount) {
        sendNotification(
            title: L.autoSwitchTitle,
            body: L.autoSwitchBody(old.organizationName ?? old.email, new.organizationName ?? new.email)
        )
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "codexbar-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func refresh() async {
        isRefreshing = true
        await WhamService.shared.refreshAll(store: store)
        store.refreshLocalCostSummary()
        store.refreshBillingHistory()
        isRefreshing = false
    }

    private func refreshAccount(_ account: TokenAccount) async {
        refreshingAccounts.insert(account.id)
        await WhamService.shared.refreshOne(account: account, store: store)
        refreshingAccounts.remove(account.id)
    }

    private func reauthAccount(_ account: TokenAccount) {
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                var updated = AccountBuilder.build(from: tokens)
                if updated.accountId == account.accountId {
                    updated.isActive = account.isActive
                    updated.tokenExpired = false
                    updated.isSuspended = false
                }
                store.addOrUpdate(updated)
                Task { await WhamService.shared.refreshOne(account: updated, store: store) }
                showSuccess = "Updated Codex configuration. Changes apply to new sessions."
            case .failure(let error):
                showError = error.localizedDescription
            }
        }
    }
}

private struct AddProviderSheet: View {
    @State private var label = ""
    @State private var baseURL = ""
    @State private var accountLabel = ""
    @State private var apiKey = ""

    let onSave: (String, String, String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Provider")
                .font(.headline)

            TextField("Provider name", text: $label)
            TextField("Base URL", text: $baseURL)
            TextField("Account label", text: $accountLabel)
            SecureField("API key", text: $apiKey)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(label, baseURL, accountLabel, apiKey)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

private struct AddProviderAccountSheet: View {
    let provider: CodexBarProvider
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var label = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Account · \(provider.label)")
                .font(.headline)

            TextField("Account label", text: $label)
            SecureField("API key", text: $apiKey)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(label, apiKey)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
