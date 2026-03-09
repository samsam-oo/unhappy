import Foundation
import CoreKit

struct DirectSessionPermissionOption: Identifiable, Equatable, Sendable {
    let id: String
    let mode: APISessionMessagePermissionMode?
    let label: String
    let description: String?
}

enum DirectSessionPermissionModeAdapter {
    static func selectedLabel(
        provider: APIUpstreamSessionProvider,
        override: APISessionMessagePermissionMode?,
        current: APISessionMessagePermissionMode?
    ) -> String {
        if let override {
            return label(for: provider, mode: override)
        }
        switch provider {
        case .codex:
            return "Local Config"
        case .claude, .gemini:
            if let current {
                return label(for: provider, mode: current)
            }
            return "Automatic"
        }
    }

    static func options(for provider: APIUpstreamSessionProvider) -> [DirectSessionPermissionOption] {
        switch provider {
        case .codex:
            return [
                DirectSessionPermissionOption(
                    id: "default",
                    mode: nil,
                    label: "Local Config",
                    description: "Use the local Codex CLI config, including ~/.codex/config.toml."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.readOnly.rawValue,
                    mode: .readOnly,
                    label: "Read Only",
                    description: "Block file edits and other write actions."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.safeYolo.rawValue,
                    mode: .safeYolo,
                    label: "Workspace Write",
                    description: "Allow workspace edits with approval protection."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.yolo.rawValue,
                    mode: .yolo,
                    label: "Full Access",
                    description: "Allow unrestricted filesystem access."
                ),
            ]
        case .claude:
            return [
                DirectSessionPermissionOption(
                    id: "default",
                    mode: nil,
                    label: "Automatic",
                    description: "Use Claude's current default permission behavior."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.acceptEdits.rawValue,
                    mode: .acceptEdits,
                    label: "Edit with Approval",
                    description: "Auto-approve edit tools while keeping other prompts interactive."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.plan.rawValue,
                    mode: .plan,
                    label: "Plan",
                    description: "Keep the session in planning mode."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.bypassPermissions.rawValue,
                    mode: .bypassPermissions,
                    label: "Full Access",
                    description: "Bypass Claude permission prompts."
                ),
            ]
        case .gemini:
            return [
                DirectSessionPermissionOption(
                    id: "default",
                    mode: nil,
                    label: "Automatic",
                    description: "Use Gemini's current approval mode."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.safeYolo.rawValue,
                    mode: .safeYolo,
                    label: "Workspace Write",
                    description: "Auto-approve safe operations and ask for riskier writes."
                ),
                DirectSessionPermissionOption(
                    id: APISessionMessagePermissionMode.yolo.rawValue,
                    mode: .yolo,
                    label: "Full Access",
                    description: "Auto-approve all Gemini actions."
                ),
            ]
        }
    }

    static func label(
        for provider: APIUpstreamSessionProvider,
        mode: APISessionMessagePermissionMode
    ) -> String {
        options(for: provider)
            .first(where: { $0.mode == mode })?
            .label ?? fallbackLabel(for: mode)
    }

    private static func fallbackLabel(for mode: APISessionMessagePermissionMode) -> String {
        switch mode {
        case .default:
            return "Automatic"
        case .acceptEdits:
            return "Edit with Approval"
        case .bypassPermissions:
            return "Full Access"
        case .plan:
            return "Plan"
        case .passthrough:
            return "Local Config"
        case .readOnly:
            return "Read Only"
        case .safeYolo:
            return "Workspace Write"
        case .yolo:
            return "Full Access"
        }
    }
}
