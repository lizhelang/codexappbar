import Foundation

protocol OpenAIAggregateGatewayLeaseStoring {
    func loadProcessIDs() -> Set<pid_t>
    func saveProcessIDs(_ processIDs: Set<pid_t>)
    func clear()
}

private struct OpenAIAggregateGatewayLeaseSnapshot: Codable, Equatable {
    var aggregateLeaseProcessIDs: [Int32]
    var updatedAt: Date
}

final class OpenAIAggregateGatewayLeaseStore: OpenAIAggregateGatewayLeaseStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = CodexPaths.openAIGatewayStateURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadProcessIDs() -> Set<pid_t> {
        guard let data = try? Data(contentsOf: self.fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(OpenAIAggregateGatewayLeaseSnapshot.self, from: data) else {
            return []
        }
        return Set(snapshot.aggregateLeaseProcessIDs.map { pid_t($0) })
    }

    func saveProcessIDs(_ processIDs: Set<pid_t>) {
        guard processIDs.isEmpty == false else {
            self.clear()
            return
        }

        try? CodexPaths.ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let snapshot = OpenAIAggregateGatewayLeaseSnapshot(
            aggregateLeaseProcessIDs: processIDs.map { Int32($0) }.sorted(),
            updatedAt: Date()
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        try? CodexPaths.writeSecureFile(data, to: self.fileURL)
    }

    func clear() {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try? self.fileManager.removeItem(at: self.fileURL)
    }
}
