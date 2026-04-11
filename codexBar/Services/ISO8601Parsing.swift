import Foundation

enum ISO8601Parsing {
    nonisolated static func parse(_ value: String) -> Date? {
        if let date = self.fractional.date(from: value) {
            return date
        }
        return self.basic.date(from: value)
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
