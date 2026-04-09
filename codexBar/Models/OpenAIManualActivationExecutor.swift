import Foundation

enum OpenAIManualActivationExecutor {
    static func execute(
        configuredBehavior: CodexBarOpenAIManualActivationBehavior,
        trigger: OpenAIManualActivationTrigger,
        activateOnly: () throws -> Void,
        launchNewInstance: () async throws -> Void
    ) async throws -> OpenAIManualActivationAction {
        let action = OpenAIManualActivationResolver.resolve(
            configuredBehavior: configuredBehavior,
            trigger: trigger
        )

        switch action {
        case .updateConfigOnly:
            try activateOnly()
        case .launchNewInstance:
            try await launchNewInstance()
        }

        return action
    }
}
