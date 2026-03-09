import SwiftUI
import CoreKit

enum SessionListRowInsets {
    static let badge = EdgeInsets(top: 6, leading: 40, bottom: 8, trailing: 40)
    static let sectionCard = EdgeInsets(top: 8, leading: 40, bottom: 8, trailing: 40)
    static let messageCard = EdgeInsets(top: 12, leading: 40, bottom: 12, trailing: 40)
    static let messageEntry = EdgeInsets(top: 12, leading: 40, bottom: 12, trailing: 40)
    static let anchor = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

extension View {
    func sessionListRow(insets: EdgeInsets) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(insets)
    }
}

struct SessionListSectionBadgeRow: View {
    let iconSystemName: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconSystemName)
                .font(.caption2)
                .foregroundStyle(AppPalette.secondaryText)
            Text(title)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(AppPalette.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

struct SessionSurfaceCard<Content: View>: View {
    let cornerRadius: CGFloat
    let fillColor: Color
    let strokeColor: Color
    let lineWidth: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 12,
        fillColor: Color = AppPalette.chatToolBackground,
        strokeColor: Color = AppPalette.chatBubbleStroke,
        lineWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: lineWidth)
            )
    }
}

enum DockChipTone {
    case neutral
    case primary
}

struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DockChipModifier: ViewModifier {
    let tone: DockChipTone

    func body(content: Content) -> some View {
        content
            .font(.caption.monospaced().weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chipBackground)
            )
    }

    private var chipBackground: Color {
        switch tone {
        case .neutral:
            return AppPalette.controlSurface
        case .primary:
            return AppPalette.chipPrimaryBackground
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            return AppPalette.primaryText
        case .primary:
            return .white
        }
    }
}

struct CodexThreadRow: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let thread: APICodexThreadSummary
    let isResuming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(threadName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if isResuming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Resume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            Text(thread.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var threadName: String {
        let trimmed = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "Untitled"
    }

    private var dateText: String? {
        let candidate = thread.updatedAt ?? thread.createdAt
        guard let candidate else { return nil }
        guard let date = Self.formatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) else {
            return candidate
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

struct ClaudeSessionRow: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let session: APIClaudeSessionSummary
    let isResuming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.id)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                if isResuming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Resume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String? {
        let candidate = session.updatedAt ?? session.createdAt
        guard let candidate else { return nil }
        guard let date = Self.formatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) else {
            return candidate
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

struct UpstreamSessionRow: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let summary: APIUpstreamSessionSummary
    let isLinking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if isLinking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let cwd = summary.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String? {
        let candidate = summary.updatedAt ?? summary.createdAt
        guard let candidate else { return nil }
        guard let date = Self.formatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) else {
            return candidate
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
