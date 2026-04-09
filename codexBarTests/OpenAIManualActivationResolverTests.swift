import XCTest

final class OpenAIManualActivationResolverTests: XCTestCase {
    func testPrimaryTapUsesConfiguredUpdateConfigOnlyBehavior() {
        let action = OpenAIManualActivationResolver.resolve(
            configuredBehavior: .updateConfigOnly,
            trigger: .primaryTap
        )

        XCTAssertEqual(action, .updateConfigOnly)
    }

    func testPrimaryTapUsesConfiguredLaunchBehavior() {
        let action = OpenAIManualActivationResolver.resolve(
            configuredBehavior: .launchNewInstance,
            trigger: .primaryTap
        )

        XCTAssertEqual(action, .launchNewInstance)
    }

    func testContextOverrideLaunchesNewInstanceEvenWhenDefaultIsUpdateConfigOnly() {
        let action = OpenAIManualActivationResolver.resolve(
            configuredBehavior: .updateConfigOnly,
            trigger: .contextOverride(.launchNewInstance)
        )

        XCTAssertEqual(action, .launchNewInstance)
    }

    func testContextOverrideUpdatesConfigOnlyEvenWhenDefaultIsLaunchNewInstance() {
        let action = OpenAIManualActivationResolver.resolve(
            configuredBehavior: .launchNewInstance,
            trigger: .contextOverride(.updateConfigOnly)
        )

        XCTAssertEqual(action, .updateConfigOnly)
    }
}
