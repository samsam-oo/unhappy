import SwiftUI
import WidgetKit
import ActivityKit
import CoreKit

@main
struct UnhappyLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        UnhappySessionsLiveActivityWidget()
    }
}

struct UnhappySessionsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UnhappySessionsActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentBadge(agent: context.state.agent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.requiresApproval {
                        Label("Approval", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Running", systemImage: "bolt.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusText)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.directory)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                AgentCompactIcon(agent: context.state.agent)
            } compactTrailing: {
                if context.state.requiresApproval {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "bolt.fill")
                }
            } minimal: {
                AgentCompactIcon(agent: context.state.agent)
            }
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<UnhappySessionsActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AgentBadge(agent: context.state.agent)
                Text(context.state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if context.state.requiresApproval {
                    Label("Approval", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Label("Running", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(context.state.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(context.state.directory)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(Color.accentColor)
    }
}

private struct AgentBadge: View {
    let agent: UnhappySessionAgentKind

    var body: some View {
        HStack(spacing: 6) {
            Image(agentAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(agentDisplayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(agentTint.opacity(0.16), in: Capsule())
            .foregroundStyle(agentTint)
    }

    private var agentDisplayName: String {
        switch agent {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .unknown:
            return "Agent"
        }
    }

    private var agentTint: Color {
        switch agent {
        case .codex:
            return .blue
        case .claude:
            return .teal
        case .gemini:
            return .purple
        case .unknown:
            return .gray
        }
    }

    private var agentAssetName: String {
        switch agent {
        case .codex:
            return "AgentCodex"
        case .claude:
            return "AgentClaude"
        case .gemini:
            return "AgentGemini"
        case .unknown:
            return "UnhappyLogo"
        }
    }
}

private struct AgentCompactIcon: View {
    let agent: UnhappySessionAgentKind

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var assetName: String {
        switch agent {
        case .codex:
            return "AgentCodex"
        case .claude:
            return "AgentClaude"
        case .gemini:
            return "AgentGemini"
        case .unknown:
            return "UnhappyLogo"
        }
    }
}
