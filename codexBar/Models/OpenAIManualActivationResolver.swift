import Foundation

enum OpenAIManualActivationTrigger: Equatable {
    case primaryTap
    case contextOverride(CodexBarOpenAIManualActivationBehavior)
}

enum OpenAIManualActivationAction: Equatable {
    case updateConfigOnly
    case launchNewInstance
}

enum OpenAIManualActivationResolver {
    static func resolve(
        configuredBehavior: CodexBarOpenAIManualActivationBehavior,
        trigger: OpenAIManualActivationTrigger
    ) -> OpenAIManualActivationAction {
        let behavior: CodexBarOpenAIManualActivationBehavior
        switch trigger {
        case .primaryTap:
            behavior = configuredBehavior
        case .contextOverride(let overrideBehavior):
            behavior = overrideBehavior
        }

        switch behavior {
        case .updateConfigOnly:
            return .updateConfigOnly
        case .launchNewInstance:
            return .launchNewInstance
        }
    }
}
