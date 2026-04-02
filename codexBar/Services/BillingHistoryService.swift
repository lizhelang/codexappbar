import Foundation

struct BillingHistoryService {
    private struct Pricing {
        let input: Double
        let output: Double
        let cachedInput: Double?
    }

    private struct BucketAccumulator {
        var providerId: String?
        var providerLabel: String
        var accountId: String?
        var accountLabel: String
        var todayCostUSD: Double = 0
        var last30DaysCostUSD: Double = 0
        var sessionCount: Int = 0
    }

    private let pricingByModel: [String: Pricing] = [
        "gpt-5": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-codex": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-mini": Pricing(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5-nano": Pricing(input: 5e-8, output: 4e-7, cachedInput: 5e-9),
        "gpt-5.1": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-max": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-mini": Pricing(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5.2": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.2-codex": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.3-codex": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.4": Pricing(input: 2.5e-6, output: 1.5e-5, cachedInput: 2.5e-7),
        "gpt-5.4-mini": Pricing(input: 7.5e-7, output: 4.5e-6, cachedInput: 7.5e-8),
        "gpt-5.4-nano": Pricing(input: 2e-7, output: 1.25e-6, cachedInput: 2e-8),
        "qwen35_4b": Pricing(input: 0, output: 0, cachedInput: 0),
    ]

    func load(config: CodexBarConfig, now: Date = Date()) -> BillingHistory {
        let snapshot = SessionLogStore.shared.snapshot()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

        let providersByID = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        let activations = snapshot.activations

        var buckets: [String: BucketAccumulator] = [:]
        var recentSessions: [BillingSessionEntry] = []

        for record in snapshot.sessions {
            guard let costUSD = self.costUSD(model: record.model, usage: record.usage) else { continue }
            let attribution = self.resolveAttribution(for: record.startedAt, activations: activations, providersByID: providersByID)
            let bucketKey = (attribution.providerId ?? "unattributed") + "::" + (attribution.accountId ?? "unattributed")

            var bucket = buckets[bucketKey] ?? BucketAccumulator(
                providerId: attribution.providerId,
                providerLabel: attribution.providerLabel,
                accountId: attribution.accountId,
                accountLabel: attribution.accountLabel
            )

            if record.startedAt >= todayStart {
                bucket.todayCostUSD += costUSD
            }
            if record.startedAt >= last30Start {
                bucket.last30DaysCostUSD += costUSD
            }
            bucket.sessionCount += 1
            buckets[bucketKey] = bucket

            recentSessions.append(
                BillingSessionEntry(
                    id: "\(record.id)-\(Int(record.startedAt.timeIntervalSince1970))",
                    startedAt: record.startedAt,
                    model: record.model,
                    costUSD: costUSD,
                    providerId: attribution.providerId,
                    providerLabel: attribution.providerLabel,
                    accountId: attribution.accountId,
                    accountLabel: attribution.accountLabel
                )
            )
        }

        let summaries = buckets.values.map { bucket in
            BillingBucketSummary(
                id: (bucket.providerId ?? "unattributed") + "::" + (bucket.accountId ?? "unattributed"),
                providerId: bucket.providerId,
                providerLabel: bucket.providerLabel,
                accountId: bucket.accountId,
                accountLabel: bucket.accountLabel,
                todayCostUSD: bucket.todayCostUSD,
                last30DaysCostUSD: bucket.last30DaysCostUSD,
                sessionCount: bucket.sessionCount
            )
        }.sorted {
            if $0.last30DaysCostUSD != $1.last30DaysCostUSD {
                return $0.last30DaysCostUSD > $1.last30DaysCostUSD
            }
            return $0.providerLabel < $1.providerLabel
        }

        let recent = recentSessions.sorted { $0.startedAt > $1.startedAt }

        return BillingHistory(
            buckets: summaries,
            recentSessions: Array(recent.prefix(10)),
            updatedAt: now
        )
    }

    private func resolveAttribution(
        for sessionDate: Date,
        activations: [SessionLogStore.ActivationRecord],
        providersByID: [String: CodexBarProvider]
    ) -> (providerId: String?, providerLabel: String, accountId: String?, accountLabel: String) {
        guard let activation = activations.last(where: { $0.timestamp <= sessionDate }),
              let providerId = activation.providerId,
              let provider = providersByID[providerId] else {
            return (nil, "Unattributed", nil, "Unknown")
        }

        let account = provider.accounts.first(where: { $0.id == activation.accountId })
        return (
            providerId,
            provider.label,
            account?.id,
            account?.label ?? "Unknown"
        )
    }

    private func costUSD(model: String, usage: SessionLogStore.Usage) -> Double? {
        guard let pricing = self.pricingByModel[model] else { return nil }
        let cached = min(max(0, usage.cachedInputTokens), max(0, usage.inputTokens))
        let nonCached = max(0, usage.inputTokens - cached)
        return Double(nonCached) * pricing.input +
            Double(cached) * (pricing.cachedInput ?? pricing.input) +
            Double(usage.outputTokens) * pricing.output
    }
}
