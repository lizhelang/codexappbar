import Foundation

final class SessionLogStore {
    static let shared = SessionLogStore()

    struct Usage {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
    }

    struct SessionRecord {
        let id: String
        let startedAt: Date
        let model: String
        let usage: Usage
    }

    struct ActivationRecord {
        let timestamp: Date
        let providerId: String?
        let accountId: String?
    }

    struct Snapshot {
        let sessions: [SessionRecord]
        let activations: [ActivationRecord]
        let updatedAt: Date
    }

    private struct FileFingerprint: Equatable {
        let fileSize: Int
        let modificationDate: Date
    }

    private struct CachedSessionRecord {
        let fingerprint: FileFingerprint
        let record: SessionRecord?
    }

    private struct CachedActivationRecords {
        let fingerprint: FileFingerprint
        let records: [ActivationRecord]
    }

    private let queue = DispatchQueue(label: "lzl.codexbar.session-log-store", qos: .utility)
    private let snapshotReuseWindow: TimeInterval = 2

    private var sessionCache: [URL: CachedSessionRecord] = [:]
    private var activationCache: CachedActivationRecords?
    private var cachedSnapshot: Snapshot?
    private var cachedSnapshotAt: Date?

    private init() {}

    func snapshot() -> Snapshot {
        self.queue.sync {
            let now = Date()
            if let cachedSnapshot = self.cachedSnapshot,
               let cachedSnapshotAt = self.cachedSnapshotAt,
               now.timeIntervalSince(cachedSnapshotAt) < self.snapshotReuseWindow {
                return cachedSnapshot
            }

            let snapshot = self.buildSnapshot(now: now)
            self.cachedSnapshot = snapshot
            self.cachedSnapshotAt = now
            return snapshot
        }
    }

    private func buildSnapshot(now: Date) -> Snapshot {
        let files = self.sessionFiles()
        var nextSessionCache: [URL: CachedSessionRecord] = [:]
        var sessions: [SessionRecord] = []
        sessions.reserveCapacity(files.count)

        for fileURL in files {
            guard let fingerprint = self.fingerprint(for: fileURL) else { continue }
            if let cached = self.sessionCache[fileURL], cached.fingerprint == fingerprint {
                nextSessionCache[fileURL] = cached
                if let record = cached.record {
                    sessions.append(record)
                }
                continue
            }

            let record = self.parseSession(fileURL)
            let cached = CachedSessionRecord(fingerprint: fingerprint, record: record)
            nextSessionCache[fileURL] = cached
            if let record {
                sessions.append(record)
            }
        }

        self.sessionCache = nextSessionCache

        let activations = self.loadActivations()
        return Snapshot(sessions: sessions, activations: activations, updatedAt: now)
    }

    private func sessionFiles() -> [URL] {
        let fileManager = FileManager.default
        let directories = [
            CodexPaths.codexRoot.appendingPathComponent("sessions", isDirectory: true),
            CodexPaths.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true),
        ]

        var files: [URL] = []
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func fingerprint(for fileURL: URL) -> FileFingerprint? {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }

        return FileFingerprint(
            fileSize: values.fileSize ?? 0,
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }

    private func parseSession(_ fileURL: URL) -> SessionRecord? {
        var sessionID: String?
        var sessionDate: Date?
        var model: String?
        var latestUsage: Usage?

        let didRead = self.enumerateLines(in: fileURL) { line in
            guard let jsonData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { return }

            switch type {
            case "session_meta":
                sessionID = payload["id"] as? String
                if let timestamp = payload["timestamp"] as? String {
                    sessionDate = ISO8601Parsing.parse(timestamp)
                }
            case "turn_context":
                if let currentModel = payload["model"] as? String {
                    model = self.normalizeModel(currentModel)
                }
            case "event_msg":
                guard let payloadType = payload["type"] as? String,
                      payloadType == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any] else { return }

                latestUsage = Usage(
                    inputTokens: total["input_tokens"] as? Int ?? 0,
                    cachedInputTokens: total["cached_input_tokens"] as? Int ?? 0,
                    outputTokens: total["output_tokens"] as? Int ?? 0
                )
            default:
                return
            }
        }

        guard didRead,
              let startedAt = sessionDate,
              let resolvedModel = model,
              let usage = latestUsage else { return nil }

        return SessionRecord(
            id: sessionID ?? fileURL.deletingPathExtension().lastPathComponent,
            startedAt: startedAt,
            model: resolvedModel,
            usage: usage
        )
    }

    private func loadActivations() -> [ActivationRecord] {
        guard let fingerprint = self.fingerprint(for: CodexPaths.switchJournalURL) else {
            self.activationCache = nil
            return []
        }

        if let activationCache = self.activationCache, activationCache.fingerprint == fingerprint {
            return activationCache.records
        }

        var records: [ActivationRecord] = []
        _ = self.enumerateLines(in: CodexPaths.switchJournalURL) { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestampString = json["timestamp"] as? String,
                  let timestamp = ISO8601Parsing.parse(timestampString) else { return }

            records.append(
                ActivationRecord(
                    timestamp: timestamp,
                    providerId: json["providerId"] as? String,
                    accountId: json["accountId"] as? String
                )
            )
        }

        records.sort { $0.timestamp < $1.timestamp }
        self.activationCache = CachedActivationRecords(fingerprint: fingerprint, records: records)
        return records
    }

    private func enumerateLines(in fileURL: URL, handleLine: (String) -> Void) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        var buffer = Data()
        let chunkSize = 64 * 1024
        let newline = UInt8(ascii: "\n")

        do {
            while let chunk = try handle.read(upToCount: chunkSize), chunk.isEmpty == false {
                buffer.append(chunk)
                while let newlineIndex = buffer.firstIndex(of: newline) {
                    self.emitLine(from: buffer[..<newlineIndex], handleLine: handleLine)
                    let nextIndex = buffer.index(after: newlineIndex)
                    buffer.removeSubrange(buffer.startIndex..<nextIndex)
                }
            }

            if buffer.isEmpty == false {
                self.emitLine(from: buffer[buffer.startIndex..<buffer.endIndex], handleLine: handleLine)
            }

            return true
        } catch {
            return false
        }
    }

    private func emitLine(from bytes: Data.SubSequence, handleLine: (String) -> Void) {
        var slice = bytes
        if slice.last == UInt8(ascii: "\r") {
            slice = slice.dropLast()
        }
        guard slice.isEmpty == false,
              let line = String(data: Data(slice), encoding: .utf8) else { return }
        handleLine(line)
    }

    private func normalizeModel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            return String(trimmed.dropFirst("openai/".count))
        }
        return trimmed
    }
}
