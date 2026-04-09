import XCTest

final class OpenAIManualActivationExecutorTests: XCTestCase {
    func testPrimaryTapExecutesConfigOnlyActivationWithoutLaunching() async throws {
        let tracker = ManualActivationEffectTracker()

        let action = try await OpenAIManualActivationExecutor.execute(
            configuredBehavior: .updateConfigOnly,
            trigger: .primaryTap
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(action, .updateConfigOnly)
        XCTAssertEqual(tracker.activateOnlyCount, 1)
        XCTAssertEqual(tracker.launchCount, 0)
    }

    func testContextOverrideLaunchExecutesLaunchPathEvenWhenDefaultIsConfigOnly() async throws {
        let tracker = ManualActivationEffectTracker()

        let action = try await OpenAIManualActivationExecutor.execute(
            configuredBehavior: .updateConfigOnly,
            trigger: .contextOverride(.launchNewInstance)
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(action, .launchNewInstance)
        XCTAssertEqual(tracker.activateOnlyCount, 0)
        XCTAssertEqual(tracker.launchCount, 1)
    }

    func testContextOverrideConfigOnlyExecutesActivationWithoutLaunchingWhenDefaultIsLaunch() async throws {
        let tracker = ManualActivationEffectTracker()

        let action = try await OpenAIManualActivationExecutor.execute(
            configuredBehavior: .launchNewInstance,
            trigger: .contextOverride(.updateConfigOnly)
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(action, .updateConfigOnly)
        XCTAssertEqual(tracker.activateOnlyCount, 1)
        XCTAssertEqual(tracker.launchCount, 0)
    }
}

private final class ManualActivationEffectTracker {
    var activateOnlyCount = 0
    var launchCount = 0
}
