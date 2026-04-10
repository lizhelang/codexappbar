import Foundation
import XCTest

@MainActor
final class MenuBarExtraVisibilityStoreTests: XCTestCase {
    func testDefaultsToInsertedWhenNoStoredValueExists() {
        let defaults = self.makeDefaults(suiteName: #function)
        let store = MenuBarExtraVisibilityStore(userDefaults: defaults)

        XCTAssertTrue(store.isInserted)
    }

    func testPersistsUpdatedInsertionState() {
        let defaults = self.makeDefaults(suiteName: #function)
        let store = MenuBarExtraVisibilityStore(userDefaults: defaults)

        store.isInserted = false

        let reopened = MenuBarExtraVisibilityStore(userDefaults: defaults)
        XCTAssertFalse(reopened.isInserted)
    }

    func testDoesNotReadVisibilityFromOtherDefaultsDomain() {
        let codexDefaults = self.makeDefaults(suiteName: "com.openai.codex.\(#function)")
        codexDefaults.set(false, forKey: MenuBarExtraVisibilityStore.userDefaultsKey)

        let codexbarDefaults = self.makeDefaults(suiteName: "lzhl.codexAppBar.\(#function)")
        let store = MenuBarExtraVisibilityStore(userDefaults: codexbarDefaults)

        XCTAssertTrue(store.isInserted)
    }

    private func makeDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
