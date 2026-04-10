import Combine
import Foundation

@MainActor
final class MenuBarExtraVisibilityStore: ObservableObject {
    nonisolated static let userDefaultsKey = "menuBarExtra.isInserted"

    @Published var isInserted: Bool {
        didSet {
            guard oldValue != self.isInserted else { return }
            self.userDefaults.set(self.isInserted, forKey: self.key)
        }
    }

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String? = nil
    ) {
        self.userDefaults = userDefaults
        self.key = key ?? Self.userDefaultsKey
        if userDefaults.object(forKey: self.key) == nil {
            self.isInserted = true
        } else {
            self.isInserted = userDefaults.bool(forKey: self.key)
        }
    }
}
