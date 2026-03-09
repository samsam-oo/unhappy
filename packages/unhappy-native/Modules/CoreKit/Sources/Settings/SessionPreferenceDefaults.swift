import Foundation

public enum SessionPreferenceDefaults {
    public static let codexModelKey = "unhappy.native.defaultModel.codex"
    public static let claudeModelKey = "unhappy.native.defaultModel.claude"
    public static let geminiModelKey = "unhappy.native.defaultModel.gemini"

    public static let codexReasoningKey = "unhappy.native.defaultReasoning.codex"
    public static let claudeReasoningKey = "unhappy.native.defaultReasoning.claude"
    public static let geminiReasoningKey = "unhappy.native.defaultReasoning.gemini"

    public static func modelKey(for agent: APISessionSpawnAgent) -> String {
        switch agent {
        case .codex:
            return codexModelKey
        case .claude:
            return claudeModelKey
        case .gemini:
            return geminiModelKey
        }
    }

    public static func reasoningKey(for agent: APISessionSpawnAgent) -> String {
        switch agent {
        case .codex:
            return codexReasoningKey
        case .claude:
            return claudeReasoningKey
        case .gemini:
            return geminiReasoningKey
        }
    }

    public static func defaultModel(
        for agent: APISessionSpawnAgent,
        defaults: UserDefaults = .standard
    ) -> String? {
        let value = defaults.string(forKey: modelKey(for: agent))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func defaultReasoningRawValue(
        for agent: APISessionSpawnAgent,
        defaults: UserDefaults = .standard
    ) -> String? {
        let value = defaults.string(forKey: reasoningKey(for: agent))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
