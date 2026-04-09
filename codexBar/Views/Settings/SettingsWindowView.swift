import Combine
import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject private var store: TokenStore
    private let codexAppPathPanelService: CodexAppPathPanelService
    private let onClose: () -> Void

    @StateObject private var coordinator: SettingsWindowCoordinator

    init(
        store: TokenStore,
        codexAppPathPanelService: CodexAppPathPanelService,
        onClose: @escaping () -> Void
    ) {
        self._store = ObservedObject(wrappedValue: store)
        self.codexAppPathPanelService = codexAppPathPanelService
        self.onClose = onClose
        self._coordinator = StateObject(
            wrappedValue: SettingsWindowCoordinator(
                config: store.config,
                accounts: store.accounts
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                self.sidebar
                Divider()
                self.detail
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let validationMessage = self.coordinator.validationMessage {
                    Text(validationMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()

                    Button(L.cancel) {
                        self.coordinator.cancelAndClose(onClose: self.onClose)
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L.save) {
                        self.coordinator.saveAndClose(
                            using: self.store,
                            onClose: self.onClose
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(self.coordinator.hasChanges == false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(self.store.$config.dropFirst()) { config in
            self.coordinator.reconcileExternalState(
                config: config,
                accounts: self.store.accounts
            )
        }
        .onReceive(self.store.$accounts.dropFirst()) { accounts in
            self.coordinator.reconcileExternalState(
                config: self.store.config,
                accounts: accounts
            )
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<SettingsWindowDraft, Value>,
        field: SettingsDirtyField
    ) -> Binding<Value> {
        Binding(
            get: { self.coordinator.draft[keyPath: keyPath] },
            set: { self.coordinator.update(keyPath, to: $0, field: field) }
        )
    }

    private var sidebar: some View {
        List {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    self.coordinator.selectedPage = page
                } label: {
                    Label(page.title, systemImage: page.iconName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(self.coordinator.selectedPage == page ? Color.accentColor.opacity(0.12) : Color.clear)
                )
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, idealWidth: 220, maxWidth: 220)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.settingsWindowTitle)
                        .font(.system(size: 20, weight: .semibold))
                    Text(L.settingsWindowHint)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch self.coordinator.selectedPage {
                case .accounts:
                    SettingsAccountsPage(coordinator: self.coordinator)
                case .usage:
                    SettingsUsagePage(coordinator: self.coordinator)
                case .codexAppPath:
                    SettingsCodexAppPathPage(
                        preferredCodexAppPath: self.binding(
                            \.preferredCodexAppPath,
                            field: .preferredCodexAppPath
                        ),
                        validationMessage: self.$coordinator.validationMessage,
                        codexAppPathPanelService: self.codexAppPathPanelService
                    )
                case .recommendationPrompt:
                    SettingsRecommendationPromptPage(
                        autoRoutingPromptMode: self.binding(
                            \.autoRoutingPromptMode,
                            field: .autoRoutingPromptMode
                        )
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsAccountsPage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.accounts.title)
                .font(.system(size: 16, weight: .semibold))

            SettingsAccountOrderingModeSection(
                mode: Binding(
                    get: { self.coordinator.draft.accountOrderingMode },
                    set: { self.coordinator.update(\.accountOrderingMode, to: $0, field: .accountOrderingMode) }
                )
            )

            SettingsManualActivationBehaviorSection(
                behavior: Binding(
                    get: { self.coordinator.draft.manualActivationBehavior },
                    set: { self.coordinator.update(\.manualActivationBehavior, to: $0, field: .manualActivationBehavior) }
                )
            )

            SettingsAccountOrderSection(coordinator: self.coordinator)
        }
    }
}

private struct SettingsUsagePage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.usage.title)
                .font(.system(size: 16, weight: .semibold))

            SettingsUsageDisplayModeSection(
                usageDisplayMode: Binding(
                    get: { self.coordinator.draft.usageDisplayMode },
                    set: { self.coordinator.update(\.usageDisplayMode, to: $0, field: .usageDisplayMode) }
                )
            )

            SettingsPopupAlertThresholdSection(
                popupAlertThresholdPercent: Binding(
                    get: { self.coordinator.draft.popupAlertThresholdPercent },
                    set: { self.coordinator.update(\.popupAlertThresholdPercent, to: $0, field: .popupAlertThresholdPercent) }
                )
            )

            SettingsQuotaSortSection(
                plusRelativeWeight: Binding(
                    get: { self.coordinator.draft.plusRelativeWeight },
                    set: { self.coordinator.update(\.plusRelativeWeight, to: $0, field: .plusRelativeWeight) }
                ),
                teamRelativeToPlusMultiplier: Binding(
                    get: { self.coordinator.draft.teamRelativeToPlusMultiplier },
                    set: { self.coordinator.update(\.teamRelativeToPlusMultiplier, to: $0, field: .teamRelativeToPlusMultiplier) }
                )
            )
        }
    }
}

private struct SettingsCodexAppPathPage: View {
    @Binding var preferredCodexAppPath: String?
    @Binding var validationMessage: String?

    let codexAppPathPanelService: CodexAppPathPanelService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.codexAppPath.title)
                .font(.system(size: 16, weight: .semibold))

            SettingsCodexAppPathSection(
                preferredCodexAppPath: self.$preferredCodexAppPath,
                validationMessage: self.$validationMessage,
                codexAppPathPanelService: self.codexAppPathPanelService
            )
        }
    }
}

private struct SettingsRecommendationPromptPage: View {
    @Binding var autoRoutingPromptMode: CodexBarAutoRoutingPromptMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.recommendationPrompt.title)
                .font(.system(size: 16, weight: .semibold))

            SettingsAutoRoutingPromptModeSection(
                promptMode: self.$autoRoutingPromptMode
            )
        }
    }
}

private struct SettingsManualActivationBehaviorSection: View {
    @Binding var behavior: CodexBarOpenAIManualActivationBehavior

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.manualActivationBehaviorTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.manualActivationBehaviorHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarOpenAIManualActivationBehavior.allCases) { option in
                    Button {
                        self.behavior = option
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.behavior == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.behavior == option ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(option.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.behavior == option ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SettingsAccountOrderingModeSection: View {
    @Binding var mode: CodexBarOpenAIAccountOrderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.accountOrderingModeTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.accountOrderingModeHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarOpenAIAccountOrderingMode.allCases) { option in
                    Button {
                        self.mode = option
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.mode == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.mode == option ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(option.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.mode == option ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SettingsAccountOrderSection: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.accountOrderTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.accountOrderHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if self.coordinator.draft.accountOrderingMode != .manual {
                Text(L.accountOrderInactiveHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if self.coordinator.orderedAccounts.isEmpty {
                Text(L.noOpenAIAccountsForOrdering)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(self.coordinator.orderedAccounts.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 12)

                            HStack(spacing: 6) {
                                Button(L.moveUp) {
                                    self.coordinator.moveAccount(accountID: item.id, offset: -1)
                                }
                                .disabled(index == 0)

                                Button(L.moveDown) {
                                    self.coordinator.moveAccount(accountID: item.id, offset: 1)
                                }
                                .disabled(index == self.coordinator.orderedAccounts.count - 1)
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                }
            }
        }
    }
}

private struct SettingsCodexAppPathSection: View {
    @Binding var preferredCodexAppPath: String?
    @Binding var validationMessage: String?

    let codexAppPathPanelService: CodexAppPathPanelService

    private var status: CodexDesktopPreferredAppPathStatus {
        CodexDesktopLaunchProbeService.preferredAppPathStatus(for: self.preferredCodexAppPath)
    }

    private var displayedPath: String {
        switch self.status {
        case .automatic:
            return self.preferredCodexAppPath ?? L.codexAppPathEmptyValue
        case .manualValid(let path), .manualInvalid(let path):
            return path
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.codexAppPathTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.codexAppPathHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(self.displayedPath)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.06))
                )

            HStack(spacing: 10) {
                Button(L.codexAppPathChooseAction) {
                    self.chooseCodexApp()
                }

                Button(L.codexAppPathResetAction) {
                    self.preferredCodexAppPath = nil
                    self.validationMessage = nil
                }
                .disabled((self.preferredCodexAppPath ?? "").isEmpty)
            }

            Text(self.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(self.statusColor)
        }
    }

    private var statusText: String {
        switch self.status {
        case .automatic:
            return L.codexAppPathAutomaticStatus
        case .manualValid:
            return L.codexAppPathUsingManualStatus
        case .manualInvalid:
            return L.codexAppPathInvalidFallbackStatus
        }
    }

    private var statusColor: Color {
        switch self.status {
        case .automatic, .manualValid:
            return .secondary
        case .manualInvalid:
            return .orange
        }
    }

    private func chooseCodexApp() {
        guard let selectedURL = self.codexAppPathPanelService.requestCodexAppURL(
            currentPath: self.preferredCodexAppPath
        ) else {
            return
        }

        guard let validatedURL = CodexDesktopLaunchProbeService.validatedPreferredCodexAppURL(
            from: selectedURL.path
        ) else {
            self.validationMessage = L.codexAppPathInvalidSelection
            return
        }

        self.preferredCodexAppPath = validatedURL.path
        self.validationMessage = nil
    }
}

private struct SettingsAutoRoutingPromptModeSection: View {
    @Binding var promptMode: CodexBarAutoRoutingPromptMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.autoRoutingPromptModeTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.autoRoutingPromptModeHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarAutoRoutingPromptMode.allCases) { mode in
                    Button {
                        self.promptMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.promptMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.promptMode == mode ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(mode.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.promptMode == mode ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SettingsUsageDisplayModeSection: View {
    @Binding var usageDisplayMode: CodexBarUsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.usageDisplayModeTitle)
                .font(.system(size: 12, weight: .medium))

            Picker(L.usageDisplayModeTitle, selection: self.$usageDisplayMode) {
                ForEach(CodexBarUsageDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct SettingsPopupAlertThresholdSection: View {
    @Binding var popupAlertThresholdPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.popupAlertThresholdTitle)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(self.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: self.$popupAlertThresholdPercent,
                in: 0...100,
                step: 5
            )

            Text(L.popupAlertThresholdHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var summary: String {
        if self.popupAlertThresholdPercent <= 0 {
            return L.popupAlertDisabled
        }
        return L.popupAlertThresholdValue(Int(self.popupAlertThresholdPercent))
    }
}

private struct SettingsQuotaSortSection: View {
    @Binding var plusRelativeWeight: Double
    @Binding var teamRelativeToPlusMultiplier: Double

    private var teamAbsoluteWeight: Double {
        self.plusRelativeWeight * self.teamRelativeToPlusMultiplier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.quotaSortSettingsTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.quotaSortSettingsHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.quotaSortPlusWeightTitle)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(L.quotaSortPlusWeightValue(self.plusRelativeWeight))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: self.$plusRelativeWeight,
                    in: CodexBarOpenAISettings.QuotaSortSettings.plusRelativeWeightRange,
                    step: 0.5
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.quotaSortTeamRatioTitle)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(
                        L.quotaSortTeamRatioValue(
                            self.teamRelativeToPlusMultiplier,
                            absoluteTeamWeight: self.teamAbsoluteWeight
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }

                Slider(
                    value: self.$teamRelativeToPlusMultiplier,
                    in: CodexBarOpenAISettings.QuotaSortSettings.teamRelativeToPlusRange,
                    step: 0.1
                )
            }
        }
    }
}

private extension SettingsPage {
    var title: String {
        switch self {
        case .accounts:
            return L.settingsAccountsPageTitle
        case .usage:
            return L.settingsUsagePageTitle
        case .codexAppPath:
            return L.settingsCodexAppPathPageTitle
        case .recommendationPrompt:
            return L.settingsRecommendationPageTitle
        }
    }

    var iconName: String {
        switch self {
        case .accounts:
            return "person.crop.circle"
        case .usage:
            return "chart.bar"
        case .codexAppPath:
            return "app.badge"
        case .recommendationPrompt:
            return "bell.badge"
        }
    }
}

private extension CodexBarOpenAIManualActivationBehavior {
    var title: String {
        switch self {
        case .updateConfigOnly:
            return L.manualActivationUpdateConfigOnly
        case .launchNewInstance:
            return L.manualActivationLaunchNewInstance
        }
    }

    var detail: String {
        switch self {
        case .updateConfigOnly:
            return L.manualActivationUpdateConfigOnlyHint
        case .launchNewInstance:
            return L.manualActivationLaunchNewInstanceHint
        }
    }
}

private extension CodexBarOpenAIAccountOrderingMode {
    var title: String {
        switch self {
        case .quotaSort:
            return L.accountOrderingModeQuotaSort
        case .manual:
            return L.accountOrderingModeManual
        }
    }

    var detail: String {
        switch self {
        case .quotaSort:
            return L.accountOrderingModeQuotaSortHint
        case .manual:
            return L.accountOrderingModeManualHint
        }
    }
}
