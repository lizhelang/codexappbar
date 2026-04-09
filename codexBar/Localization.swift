import Foundation

/// Bilingual string helper — detects system language at runtime, with user override.
enum L {
    /// nil = follow system, true = force Chinese, false = force English
    nonisolated static var languageOverride: Bool? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "languageOverride") != nil else { return nil }
            return d.bool(forKey: "languageOverride")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "languageOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "languageOverride")
            }
        }
    }

    nonisolated static var zh: Bool {
        if let override = languageOverride { return override }
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        return lang.hasPrefix("zh")
    }

    // MARK: - Status Bar
    static var weeklyLimit: String { zh ? "周限额" : "Weekly Limit" }
    static var hourLimit: String   { zh ? "5h限额" : "5h Limit" }

    // MARK: - MenuBarView
    static var noAccounts: String      { zh ? "还没有账号"          : "No Accounts" }
    static var addAccountHint: String  { zh ? "点击下方 + 添加账号"   : "Tap + below to add an account" }
    static var refreshUsage: String    { zh ? "刷新用量"            : "Refresh Usage" }
    static var addAccount: String      { zh ? "添加账号"            : "Add Account" }
    static var openAICSVToolbar: String { zh ? "导入或导出 OpenAI CSV" : "Import or Export OpenAI CSV" }
    static func codexLaunchSwitchedInstanceStarted(_ account: String) -> String {
        zh ? "已切换到「\(account)」，并为该账号新开一个 Codex 实例。" : "Switched to \"\(account)\" and launched a new Codex instance for it."
    }
    static var codexLaunchProbeAppNotFound: String {
        zh ? "未找到 Codex.app" : "Codex.app was not found"
    }
    static var codexLaunchProbeExecutableMissing: String {
        zh ? "未找到 bundled codex 可执行文件" : "The bundled codex executable was not found"
    }
    static var codexLaunchProbeTimedOut: String {
        zh ? "启动 Codex.app 超时" : "Launching Codex.app timed out"
    }
    static func codexLaunchProbeFailed(_ message: String) -> String {
        zh ? "受管启动探针失败：\(message)" : "Managed launch probe failed: \(message)"
    }
    static var exportOpenAICSVAction: String { zh ? "导出 OpenAI CSV…" : "Export OpenAI CSV…" }
    static var importOpenAICSVAction: String { zh ? "导入 OpenAI CSV…" : "Import OpenAI CSV…" }
    static var settings: String { zh ? "设置" : "Settings" }
    static var settingsWindowTitle: String { self.settings }
    static var settingsWindowHint: String {
        zh
            ? "左侧切换账户、用量、Codex App 路径和弹窗推荐设置。窗口内的修改会先保存在草稿里，点击保存后再统一生效。"
            : "Use the sidebar to switch between account, usage, Codex App path, and recommendation prompt settings. Changes stay in a window draft until you save."
    }
    static var settingsAccountsPageTitle: String { zh ? "账户设置" : "Account Settings" }
    static var settingsUsagePageTitle: String { zh ? "用量设置" : "Usage Settings" }
    static var settingsCodexAppPathPageTitle: String { zh ? "Codex App 路径设置" : "Codex App Path" }
    static var settingsRecommendationPageTitle: String { zh ? "弹窗推荐设置" : "Recommendation Prompt Settings" }
    static var usageDisplayModeTitle: String { zh ? "用量显示方式" : "Usage Display" }
    static var remainingUsageDisplay: String { zh ? "剩余用量" : "Remaining Quota" }
    static var usedQuotaDisplay: String { zh ? "已用额度" : "Used Quota" }
    static var remainingShort: String { zh ? "剩余" : "Remaining" }
    static var usedShort: String { zh ? "已用" : "Used" }
    static var quotaSortSettingsTitle: String { zh ? "用量排序参数" : "Quota Sort Parameters" }
    static var quotaSortSettingsHint: String {
        zh
            ? "排序仍按用量规则计算，正在使用和运行中的账号优先。这里仅调整套餐权重换算：默认 free=1、plus=10、team=plus×1.5。"
            : "Sorting still follows quota usage rules, with active and running accounts first. These controls only adjust plan weighting: by default free=1, plus=10, and team=plus×1.5."
    }
    static var quotaSortPlusWeightTitle: String { zh ? "Plus 相对 Free 权重" : "Plus Weight vs Free" }
    static var quotaSortTeamRatioTitle: String { zh ? "Team 相对 Plus 倍数" : "Team Ratio vs Plus" }
    static func quotaSortPlusWeightValue(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return zh ? "plus=\(formatted)" : "plus=\(formatted)"
    }
    static func quotaSortTeamRatioValue(_ value: Double, absoluteTeamWeight: Double) -> String {
        let ratio = String(format: "%.1f", value)
        let teamWeight = String(format: "%.1f", absoluteTeamWeight)
        return zh ? "team=plus×\(ratio) (= \(teamWeight))" : "team=plus×\(ratio) (= \(teamWeight))"
    }
    static var popupAlertThresholdTitle: String { zh ? "弹窗用量告警阈值" : "Popup Usage Alert Threshold" }
    static var popupAlertThresholdHint: String {
        zh
            ? "当任一窗口的剩余用量低于该值时，在账号列表和菜单栏图标中高亮提示；启用自动切换时，也会用于推荐切换弹窗。设为 0% 可关闭。"
            : "Highlight the account list and menu bar icon when any window's remaining quota drops below this value. When auto-switch is enabled, the same threshold also drives the recommended switch popup. Set to 0% to disable."
    }
    static func popupAlertThresholdValue(_ value: Int) -> String {
        zh ? "剩余 ≤ \(value)%" : "Remaining <= \(value)%"
    }
    static var popupAlertDisabled: String { zh ? "已关闭" : "Off" }
    static var accountOrderTitle: String { zh ? "OpenAI 账号顺序" : "OpenAI Account Order" }
    static var accountOrderingModeTitle: String { zh ? "账号排序方式" : "Account Ordering" }
    static var accountOrderingModeHint: String {
        zh
            ? "可在“按用量排序”和“按手动顺序”之间切换。只有切到手动顺序时，下面的手动排序才会影响主菜单展示。"
            : "Switch between quota-based sorting and manual order. The manual list below only affects the main menu when manual order is selected."
    }
    static var accountOrderingModeQuotaSort: String { zh ? "按用量排序" : "Sort by Quota" }
    static var accountOrderingModeQuotaSortHint: String {
        zh ? "直接按当前用量权重排序，剩余可用更多的账号优先。" : "Use the current quota-weighted ranking directly, with accounts that have more usable quota first."
    }
    static var accountOrderingModeManual: String { zh ? "按手动顺序" : "Manual Order" }
    static var accountOrderingModeManualHint: String {
        zh ? "按你保存的手动顺序展示；active / running 账号仍会临时浮顶。" : "Use your saved manual order for display; active and running accounts still float to the top temporarily."
    }
    static var accountOrderHint: String {
        zh
            ? "这里定义手动顺序。只有在上方选了“按手动顺序”后它才生效；active / running 账号仍会临时浮顶。"
            : "This defines the manual order. It only takes effect when \"Manual Order\" is selected above, and active/running accounts still float to the top."
    }
    static var accountOrderInactiveHint: String {
        zh ? "当前按用量排序；你仍可预先调整手动顺序，等切到“按手动顺序”后再生效。" : "Quota sorting is currently active. You can still prepare the manual order below, and it will apply once you switch to Manual Order."
    }
    static var noOpenAIAccountsForOrdering: String { zh ? "当前没有可排序的 OpenAI 账号。" : "There are no OpenAI accounts to reorder." }
    static var moveUp: String { zh ? "上移" : "Move Up" }
    static var moveDown: String { zh ? "下移" : "Move Down" }
    static var manualActivationBehaviorTitle: String { zh ? "手动点击 OpenAI 账号时" : "When Manually Clicking an OpenAI Account" }
    static var manualActivationBehaviorHint: String {
        zh
            ? "只影响 OpenAI OAuth 账号的手动点击。它不会影响自动推荐弹窗，也不会扩展到 custom provider。"
            : "This only affects manual clicks on OpenAI OAuth accounts. It does not affect auto-routing recommendation prompts or custom providers."
    }
    static var manualActivationUpdateConfigOnly: String { zh ? "仅修改配置" : "Update Config Only" }
    static var manualActivationUpdateConfigOnlyHint: String {
        zh ? "仅切换当前 active account 并同步配置，本次不新开 Codex 实例。" : "Switch the active account and sync config without launching a new Codex instance."
    }
    static var manualActivationLaunchNewInstance: String { zh ? "新开实例" : "Launch New Instance" }
    static var manualActivationLaunchNewInstanceHint: String {
        zh ? "切换账号后立刻拉起一个新的 Codex App 实例。" : "Switch the account and immediately launch a new Codex App instance."
    }
    static var manualActivationUpdateConfigOnlyOneTime: String { zh ? "仅修改配置（本次）" : "Update Config Only (This Time)" }
    static var manualActivationLaunchNewInstanceOneTime: String { zh ? "新开实例（本次）" : "Launch New Instance (This Time)" }
    static var save: String { zh ? "保存" : "Save" }
    static var codexAppPathTitle: String { zh ? "Codex.app 路径" : "Codex.app Path" }
    static var codexAppPathHint: String {
        zh
            ? "手动路径优先；路径失效时会自动回退系统探测。有效路径必须是绝对路径、指向 Codex.app，并包含 Contents/Resources/codex。"
            : "A manual path takes priority, but invalid paths fall back to automatic detection. Valid paths must be absolute, point to Codex.app, and include Contents/Resources/codex."
    }
    static var codexAppPathChooseAction: String { zh ? "选择…" : "Choose…" }
    static var codexAppPathResetAction: String { zh ? "恢复自动探测" : "Use Auto Detection" }
    static var codexAppPathPanelTitle: String { zh ? "选择 Codex.app" : "Choose Codex.app" }
    static var codexAppPathPanelMessage: String {
        zh ? "请选择一个有效的 Codex.app。" : "Choose a valid Codex.app."
    }
    static var codexAppPathEmptyValue: String { zh ? "当前未设置手动路径" : "No manual path selected" }
    static var codexAppPathUsingManualStatus: String { zh ? "使用手动路径" : "Using the manual path" }
    static var codexAppPathInvalidFallbackStatus: String { zh ? "手动路径无效，已回退自动探测" : "Manual path is invalid; falling back to automatic detection" }
    static var codexAppPathAutomaticStatus: String { zh ? "当前使用自动探测" : "Currently using automatic detection" }
    static var codexAppPathInvalidSelection: String {
        zh
            ? "所选路径不是有效的 Codex.app。请确认它是绝对路径、名为 Codex.app，并包含 Contents/Resources/codex。"
            : "The selected path is not a valid Codex.app. Make sure it is an absolute path named Codex.app and includes Contents/Resources/codex."
    }
    static var autoRoutingPromptModeTitle: String { zh ? "自动切换推荐弹窗" : "Auto-Switch Recommendation Prompt" }
    static var autoRoutingPromptModeHint: String {
        zh
            ? "仅影响 autoThreshold 推荐；autoUnavailable / autoExhausted 仍会走独立 forced failover 保护。"
            : "This only affects autoThreshold recommendations. autoUnavailable and autoExhausted still use forced failover protection."
    }
    static var autoRoutingPromptModeLaunchNewInstance: String { zh ? "切换并新开实例" : "Switch and Launch New Instance" }
    static var autoRoutingPromptModeLaunchNewInstanceHint: String {
        zh ? "确认后切账号、新开 Codex.app，并关闭旧实例。" : "After confirmation, switch accounts, launch a new Codex.app instance, and close the old one."
    }
    static var autoRoutingPromptModeRemindOnly: String { zh ? "只弹窗提醒" : "Remind Only" }
    static var autoRoutingPromptModeRemindOnlyHint: String {
        zh ? "只提示推荐账号，不切账号、不新开实例，也不关闭旧实例。" : "Only show the recommendation. Do not switch accounts, launch a new instance, or close the old one."
    }
    static var autoRoutingPromptModeDisabled: String { zh ? "关闭推荐弹窗" : "Disable Recommendation Prompt" }
    static var autoRoutingPromptModeDisabledHint: String {
        zh ? "彻底关闭阈值型推荐弹窗，但不影响 forced failover。" : "Turn off threshold-based recommendation prompts without affecting forced failover."
    }
    static var openAICSVExportPrompt: String { zh ? "导出" : "Export" }
    static var openAICSVImportPrompt: String { zh ? "导入" : "Import" }
    static var openAICSVRiskTitle: String { zh ? "导出将包含敏感 OAuth token" : "Export Includes Sensitive OAuth Tokens" }
    static var openAICSVRiskMessage: String {
        zh
            ? "导出的 CSV 将包含 access_token、refresh_token 和 id_token。请仅保存到受信任位置，避免分享或同步到不安全环境。"
            : "The exported CSV includes access_token, refresh_token, and id_token. Save it only to a trusted location and avoid sharing or syncing it to insecure destinations."
    }
    static var openAICSVRiskConfirm: String { zh ? "继续导出" : "Export Anyway" }
    static var noOpenAIAccountsToExport: String {
        zh ? "没有可导出的 OpenAI 账号" : "No OpenAI accounts available to export"
    }
    static func openAICSVExportSucceeded(_ count: Int) -> String {
        zh ? "已导出 \(count) 个 OpenAI 账号到 CSV。" : "Exported \(count) OpenAI account\(count == 1 ? "" : "s") to CSV."
    }
    static func openAICSVImportSucceeded(
        added: Int,
        updated: Int,
        activeChanged: Bool,
        providerChanged: Bool,
        preservedCompatibleProvider: Bool
    ) -> String {
        let prefix = zh
            ? "已导入 OpenAI CSV：新增 \(added) 个，覆盖 \(updated) 个。"
            : "Imported OpenAI CSV: \(added) added, \(updated) updated."
        let suffix: String
        if preservedCompatibleProvider {
            suffix = zh ? " 当前使用 provider 保持不变。" : " The current provider was left unchanged."
        } else if providerChanged {
            suffix = zh ? " 当前 provider 已切换到 OpenAI。" : " The current provider was switched to OpenAI."
        } else if activeChanged {
            suffix = zh ? " 当前 OpenAI 账号已更新。" : " The current OpenAI account was updated."
        } else {
            suffix = zh ? " 当前 active 选择未变化。" : " The current active selection was unchanged."
        }
        return prefix + suffix
    }
    static var openAICSVEmptyFile: String { zh ? "CSV 为空，或只有表头。" : "The CSV is empty or only contains a header." }
    static var openAICSVMissingColumns: String { zh ? "CSV 缺少必需列。" : "The CSV is missing required columns." }
    static var openAICSVUnsupportedVersion: String { zh ? "不支持的 CSV 版本。" : "Unsupported CSV format version." }
    static func openAICSVInvalidRow(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行格式无效。" : "CSV row \(row) has an invalid format."
    }
    static func openAICSVMissingRequiredValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行缺少必填字段。" : "CSV row \(row) is missing required fields."
    }
    static func openAICSVInvalidAccount(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 token 校验失败。" : "CSV row \(row) failed token validation."
    }
    static func openAICSVAccountIDMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 account_id 校验失败。" : "CSV row \(row) failed account_id validation."
    }
    static func openAICSVEmailMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 email 校验失败。" : "CSV row \(row) failed email validation."
    }
    static var openAICSVDuplicateAccounts: String { zh ? "CSV 中存在重复的 account_id。" : "The CSV contains duplicate account_id values." }
    static var openAICSVMultipleActiveAccounts: String { zh ? "CSV 中包含多个 is_active=true 的账号。" : "The CSV contains multiple accounts marked as is_active=true." }
    static func openAICSVInvalidActiveValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 is_active 值无效。" : "CSV row \(row) has an invalid is_active value."
    }
    static var quit: String            { zh ? "退出"               : "Quit" }
    static var switchAccount: String    { zh ? "切换账号"            : "Switch Account" }
    static var switchTitle: String     { zh ? "切换账号"            : "Switch Account" }
    static var continueRestart: String { zh ? "继续"               : "Continue" }
    static var cancel: String          { zh ? "取消"               : "Cancel" }
    static var justUpdated: String     { zh ? "刚刚更新"            : "Just updated" }
    static var restartCodexTitle: String {
        zh ? "Codex.app 正在运行" : "Codex.app is Running"
    }
    static var restartCodexInfo: String {
        zh
            ? "账号已切换完成。\n\n如需立即生效，可强制退出 Codex.app（可选是否自动重新打开）。\n\n⚠️ 警告：强制退出将终止所有 subagent 任务，可能导致进行中的任务丢失，请谨慎操作。"
            : "Account switched successfully.\n\nYou may force-quit Codex.app now to apply the change (optionally reopen it).\n\n⚠️ Warning: Force-quitting will kill all running subagent tasks. Make sure no important tasks are in progress."
    }
    static var forceQuitAndReopen: String { zh ? "强制退出并重新打开" : "Force Quit & Reopen" }
    static var forceQuitOnly: String    { zh ? "仅强制退出" : "Force Quit Only" }
    static var restartLater: String     { zh ? "稍后手动重启" : "Later" }

    static func available(_ n: Int, _ total: Int) -> String {
        zh ? "\(n)/\(total) 可用" : "\(n)/\(total) Available"
    }
    static func minutesAgo(_ m: Int) -> String {
        zh ? "\(m) 分钟前更新" : "Updated \(m) min ago"
    }
    static func hoursAgo(_ h: Int) -> String {
        zh ? "\(h) 小时前更新" : "Updated \(h) hr ago"
    }
    static var switchWarningTitle: String {
        zh ? "⚠️ 实验性功能 — 账号切换" : "⚠️ Experimental — Account Switch"
    }
    static func switchConfirm(_ name: String) -> String { switchWarning(name) }
    static func switchConfirmMsg(_ name: String) -> String { switchWarning(name) }
    static func switchWarning(_ name: String) -> String {
        zh
            ? "⚠️ 实验性功能\n\n将切换到「\(name)」。\n\n此功能通过直接修改配置文件实现辅助切换，需要退出整个 Codex.app 才能生效。退出过程中可能导致数据丢失！\n\n如果你正在使用 subagent，强烈建议通过软件内的退出登录功能重新登录其他账号，而非使用此切换方案。"
            : "⚠️ Experimental Feature\n\nSwitching to \"\(name)\".\n\nThis feature works by modifying the config file directly. Codex.app must be fully quit to apply the change, which may cause data loss.\n\nIf you are using subagents, it is strongly recommended to log out from within Codex.app and log in with another account instead."
    }

    // MARK: - Auto switch
    static var autoSwitchTitle: String {
        zh ? "已自动切换账号" : "Account Auto-Switched"
    }
    static var autoSwitchPromptTitle: String {
        zh ? "推荐切换并新开实例" : "Recommended: Switch and Launch New Instance"
    }
    static func autoSwitchPromptBody(_ from: String, _ to: String) -> String {
        zh
            ? "当前账号「\(from)」额度已接近阈值。\n\n推荐切换到「\(to)」，并新开一个 Codex 实例。\n\n如果你点“确定”，Codexbar 会切到推荐账号，启动一个新实例，然后关闭当前运行中的 Codex 实例。"
            : "The current account \"\(from)\" is close to its quota threshold.\n\nCodexbar recommends switching to \"\(to)\" and launching a new Codex instance.\n\nIf you choose Confirm, Codexbar will switch to the recommended account, launch a new instance, and close the currently running Codex instance."
    }
    static var autoSwitchReminderTitle: String {
        zh ? "推荐切换账号" : "Recommended Account Switch"
    }
    static func autoSwitchReminderBody(_ from: String, _ to: String) -> String {
        zh
            ? "当前账号「\(from)」额度已接近阈值。\n\n建议下一次切换到「\(to)」。\n\n当前模式仅提醒，不会自动切账号、不会新开实例，也不会关闭旧实例。若要切换，请在账号列表中手动点击“使用”。"
            : "The current account \"\(from)\" is close to its quota threshold.\n\nCodexbar recommends switching to \"\(to)\" next.\n\nThis mode is reminder-only: it will not switch accounts, launch a new instance, or close the current one. Use the account list's Use button if you want to switch manually."
    }
    static var confirm: String { zh ? "确定" : "Confirm" }
    static var acknowledge: String { zh ? "知道了" : "OK" }
    static func autoSwitchBody(_ from: String, _ to: String) -> String {
        zh
            ? "「\(from)」额度不足，已自动切换至「\(to)」"
            : "Quota low on \"\(from)\", switched to \"\(to)\""
    }
    static var autoSwitchNoCandidates: String {
        zh
            ? "所有账号额度不足或不可用，请手动处理"
            : "All accounts are low or unavailable, please take action"
    }

    // MARK: - AccountRowView
    static var reauth: String          { zh ? "重新授权"     : "Re-authorize" }
    static var useBtn: String          { zh ? "使用"         : "Use" }
    static var switchBtn: String       { useBtn }
    static var tokenExpiredMsg: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var bannedMsg: String       { zh ? "账号已停用"   : "Account suspended" }
    static var deleteBtn: String       { zh ? "删除"         : "Delete" }
    static var deleteConfirm: String   { zh ? "删除"         : "Delete" }
    static var nextUseTitle: String    { zh ? "下一次使用"   : "Next Use" }
    static var inUseNone: String       { zh ? "未检测到正在使用的 OpenAI 会话" : "No live OpenAI sessions detected" }
    static var runningThreadNone: String { zh ? "未检测到运行中的 OpenAI 线程" : "No running OpenAI threads detected" }
    static var runningThreadUnavailable: String { zh ? "运行中状态不可用" : "Running status unavailable" }
    static var runningThreadUnavailableRuntimeLogMissing: String {
        zh ? "运行中状态不可用（未找到运行日志库）" : "Running status unavailable (runtime log database missing)"
    }
    static var runningThreadUnavailableRuntimeLogUninitialized: String {
        zh ? "运行中状态不可用（运行日志库未初始化）" : "Running status unavailable (runtime logs not initialized)"
    }

    static func inUseSessions(_ count: Int) -> String {
        zh ? "使用中 · \(count) 个会话" : "In Use · \(count) session\(count == 1 ? "" : "s")"
    }

    static func runningThreads(_ count: Int) -> String {
        zh ? "运行中 · \(count) 个线程" : "Running · \(count) thread\(count == 1 ? "" : "s")"
    }

    static func inUseSummary(_ sessions: Int, _ accounts: Int) -> String {
        if zh {
            return "使用中 · \(sessions) 个会话 / \(accounts) 个账号"
        }
        return "In Use · \(sessions) session\(sessions == 1 ? "" : "s") across \(accounts) account\(accounts == 1 ? "" : "s")"
    }

    static func runningThreadSummary(_ threads: Int, _ accounts: Int) -> String {
        if zh {
            return "运行中 · \(threads) 个线程 / \(accounts) 个账号"
        }
        return "Running · \(threads) thread\(threads == 1 ? "" : "s") / \(accounts) account\(accounts == 1 ? "" : "s")"
    }

    static func inUseUnknownSessions(_ count: Int) -> String {
        zh ? "另有 \(count) 个未归因会话" : "\(count) unattributed session\(count == 1 ? "" : "s")"
    }

    static func runningThreadUnknown(_ count: Int) -> String {
        zh ? "另有 \(count) 个未归因线程" : "\(count) unattributed thread\(count == 1 ? "" : "s")"
    }

    static func deletePrompt(_ name: String) -> String {
        zh ? "确认删除 \(name)？" : "Delete \(name)?"
    }
    static func confirmDelete(_ name: String) -> String { deletePrompt(name) }
    static var delete: String         { zh ? "删除"     : "Delete" }
    static var tokenExpiredHint: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var accountSuspended: String { zh ? "账号已停用" : "Account suspended" }
    static var weeklyExhausted: String  { zh ? "周额度耗尽" : "Weekly quota exhausted" }
    static var primaryExhausted: String { zh ? "5h 额度耗尽" : "5h quota exhausted" }
    nonisolated static func compactResetDaysHours(_ days: Int, _ hours: Int) -> String {
        zh ? "\(days)天\(hours)时" : "\(days)d \(hours)h"
    }
    nonisolated static func compactResetHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        zh ? "\(hours)时\(minutes)分" : "\(hours)h \(minutes)m"
    }
    nonisolated static func compactResetMinutes(_ minutes: Int) -> String {
        zh ? "\(minutes)分" : "\(minutes)m"
    }
    nonisolated static var compactResetSoon: String {
        zh ? "1分内" : "<1m"
    }

    // MARK: - TokenAccount status
    static var statusOk: String       { zh ? "正常"     : "OK" }
    static var statusWarning: String  { zh ? "即将用尽" : "Warning" }
    static var statusExceeded: String { zh ? "额度耗尽" : "Exceeded" }
    static var statusBanned: String   { zh ? "已停用"   : "Suspended" }

    // MARK: - Reset countdown
    static var resetSoon: String { zh ? "即将重置" : "Resetting soon" }
    static func resetInMin(_ m: Int) -> String {
        zh ? "\(m) 分钟后重置" : "Resets in \(m) min"
    }
    static func resetInHr(_ h: Int, _ m: Int) -> String {
        zh ? "\(h) 小时 \(m) 分后重置" : "Resets in \(h)h \(m)m"
    }
    static func resetInDay(_ d: Int, _ h: Int) -> String {
        zh ? "\(d) 天 \(h) 小时后重置" : "Resets in \(d)d \(h)h"
    }
}
