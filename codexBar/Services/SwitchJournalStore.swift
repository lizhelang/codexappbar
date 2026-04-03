import Foundation

struct SwitchJournalStore {
    func appendActivation(providerID: String?, accountID: String?) throws {
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "providerId": providerID as Any,
            "accountId": accountID as Any,
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
}
