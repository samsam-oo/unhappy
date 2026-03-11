import Foundation
import SwiftUI
import CoreKit
import SessionKit
import UIFoundation

struct SessionTranscriptMarkdownView: View {
    let markdown: String
    let role: SessionTranscriptEntryRole
    let kind: SessionTranscriptEntryKind
    let onOpenFilePath: (String) -> Void

    private var blocks: [SessionMarkdownBlock] {
        SessionTranscriptRichContentParser.markdownBlocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(AppPalette.accent)
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL {
                let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    onOpenFilePath(path)
                    return .handled
                }
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func blockView(_ block: SessionMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level: level))
                .foregroundStyle(AppPalette.primaryText)
        case .paragraph(let text):
            inlineText(text)
                .font(kind == .thinking ? .callout : .body)
                .foregroundStyle(kind == .thinking ? AppPalette.secondaryText : AppPalette.primaryText)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.callout)
                    .foregroundStyle(AppPalette.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.chatToolBackground.opacity(0.8))
            )
        case .code(let language, let code):
            SessionTranscriptMonospaceBlock(
                text: code,
                language: language,
                accentColor: role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent
            )
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.marker)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(width: 22 + CGFloat(item.depth * 14), alignment: .leading)
                        inlineText(item.text)
                            .font(.callout)
                            .foregroundStyle(AppPalette.primaryText)
                    }
                }
            }
        case .image(let altText, let source):
            SessionTranscriptInlineImageView(
                source: source,
                altText: altText.isEmpty ? "Image" : altText
            )
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attributed = SessionTranscriptRichContentParser.attributedInlineMarkdown(raw) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.bold)
        case 2:
            return .title3.weight(.semibold)
        case 3:
            return .headline.weight(.semibold)
        default:
            return .subheadline.weight(.semibold)
        }
    }
}

struct SessionTranscriptToolRichContentView: View {
    let entry: SessionTranscriptEntry

    private var richContent: SessionTranscriptRichToolContent? {
        SessionTranscriptRichContentParser.richToolContent(for: entry)
    }

    var body: some View {
        if let richContent {
            switch richContent {
            case .commandExecution(let command):
                commandExecutionCard(command)
            case .fileChanges(let changes):
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(changes) { change in
                        fileChangeCard(change)
                    }
                }
            case .diff(let files):
                diffFileList(files, compact: false)
            case .toolDetails(let tool):
                genericToolCard(tool)
            }
        } else {
            SessionTranscriptMonospaceBlock(
                text: entry.body,
                language: nil,
                accentColor: AppPalette.terminalLineTool
            )
        }
    }

    @ViewBuilder
    private func genericToolCard(
        _ tool: SessionTranscriptGenericToolPresentation
    ) -> some View {
        let badgeTint = genericToolBadgeTint(tool.badgeTone)
        SessionSurfaceCard(
            cornerRadius: 14,
            fillColor: AppPalette.chatToolBackground.opacity(0.95),
            strokeColor: badgeTint.opacity(tool.badgeText == nil ? 0.18 : 0.24)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: genericToolSymbolName(tool.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeTint)
                    Text(tool.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                    if let badgeText = tool.badgeText, !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(badgeTint.opacity(0.12))
                            )
                    }
                    Spacer(minLength: 0)
                }

                if let compactSummary = tool.compactSummary, !compactSummary.isEmpty {
                    Text(compactSummary)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                        .textSelection(.enabled)
                }

                if let subtitle = tool.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if !tool.planItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tool.planItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.status.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(planStatusTint(item.status))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.step)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(AppPalette.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.status.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(planStatusTint(item.status))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(planStatusTint(item.status).opacity(0.12))
                                        )
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if !tool.fields.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tool.fields) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .frame(width: 88, alignment: .leading)
                                Text(field.value)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppPalette.primaryText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let body = tool.body, !body.isEmpty {
                    SessionTranscriptMonospaceBlock(
                        text: body,
                        language: nil,
                        accentColor: badgeTint
                    )
                }
            }
            .padding(12)
        }
    }

    private func genericToolSymbolName(
        _ kind: SessionTranscriptGenericToolPresentation.Kind
    ) -> String {
        switch kind {
        case .plan:
            return "checklist"
        case .spawnAgent:
            return "person.badge.plus"
        case .wait:
            return "hourglass"
        case .stdin:
            return "arrow.up.to.line.compact"
        case .toolResult:
            return "checkmark.circle"
        case .toolCall:
            return "hammer"
        }
    }

    private func genericToolBadgeTint(
        _ tone: SessionTranscriptGenericToolPresentation.BadgeTone
    ) -> Color {
        switch tone {
        case .accent:
            return AppPalette.accent
        case .success:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return AppPalette.secondaryText
        }
    }

    private func planStatusTint(
        _ status: SessionTranscriptPlanStepPresentation.Status
    ) -> Color {
        switch status {
        case .pending:
            return AppPalette.secondaryText
        case .inProgress:
            return AppPalette.accent
        case .completed:
            return .green
        }
    }

    @ViewBuilder
    private func commandExecutionCard(
        _ command: SessionTranscriptCommandRunPresentation
    ) -> some View {
        SessionSurfaceCard(
            cornerRadius: 14,
            fillColor: AppPalette.chatToolBackground.opacity(0.96),
            strokeColor: commandStatusTint(command.status).opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(commandStatusTint(command.status))
                    Text("Ran command")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                    statusBadge(for: command)
                    Spacer(minLength: 0)
                    Text(command.command)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPalette.secondaryText)
                        .lineLimit(1)
                    if let exitCode = command.exitCode {
                        Text("Exit code \(exitCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    if let durationText = command.durationText {
                        Text(durationText)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }
                SessionTranscriptMonospaceBlock(
                    text: "$ " + command.command,
                    language: "shell",
                    accentColor: commandStatusTint(command.status)
                )

                if let cwd = command.cwd {
                    LabeledContent {
                        Text(cwd)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    } label: {
                        Text("Shell")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }

                if let summary = command.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                } else if command.logs?.isEmpty != false {
                    Text(command.waitingDescription)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if !command.actions.isEmpty {
                    explorationStack(for: command.actions)
                }

                if let logs = command.logs, !logs.isEmpty {
                    ScrollView(.vertical) {
                        SessionTranscriptMonospaceBlock(
                            text: logs,
                            language: nil,
                            accentColor: commandStatusTint(command.status)
                        )
                    }
                    .frame(maxHeight: 240)
                }

                if !command.supplementalEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(command.supplementalEntries) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .foregroundStyle(AppPalette.secondaryText)
                                if item.kind == .toolResult {
                                    ScrollView(.vertical) {
                                        SessionTranscriptMonospaceBlock(
                                            text: item.body,
                                            language: nil,
                                            accentColor: commandStatusTint(command.status)
                                        )
                                    }
                                    .frame(maxHeight: 220)
                                } else {
                                    SessionTranscriptMonospaceBlock(
                                        text: item.body,
                                        language: nil,
                                        accentColor: AppPalette.accent
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func explorationStack(
        for actions: [SessionTranscriptCommandExecutionPayload.Action]
    ) -> some View {
        SessionSurfaceCard(
            cornerRadius: 12,
            fillColor: AppPalette.controlSurface.opacity(0.92),
            strokeColor: AppPalette.chromeSurfaceStroke.opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppPalette.secondaryText)
                        .frame(width: 6, height: 6)
                    Text("Explored")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                }

                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    let branch = index == actions.count - 1 ? "└" : "├"
                    HStack(alignment: .top, spacing: 8) {
                        Text(branch)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                        Text(action.kind.label)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text(action.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.primaryText)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 14)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func fileChangeCard(_ change: SessionTranscriptFileChangePresentation) -> some View {
        let tint = fileChangeTint(change.kind)
        SessionSurfaceCard(
            cornerRadius: 12,
            fillColor: AppPalette.chatToolBackground.opacity(0.95),
            strokeColor: tint.opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: change.kind.iconSystemName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(SessionTranscriptRichContentParser.fileName(from: change.path))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(change.kind.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.14))
                        )
                }

                Text(change.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
                    .textSelection(.enabled)

                if let movePath = change.movePath, !movePath.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(movePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .textSelection(.enabled)
                    }
                }

                if let summary = change.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if !change.diffFiles.isEmpty {
                    diffFileList(change.diffFiles, compact: true)
                }
            }
            .padding(12)
        }
    }

    private func fileChangeTint(_ kind: SessionTranscriptFileChangeKind) -> Color {
        switch kind {
        case .added:
            return .green
        case .deleted:
            return .red
        case .modified:
            return AppPalette.accent
        case .moved:
            return .orange
        case .unknown:
            return AppPalette.secondaryText
        }
    }

    @ViewBuilder
    private func statusBadge(
        for command: SessionTranscriptCommandRunPresentation
    ) -> some View {
        HStack(spacing: 6) {
            statusDot(for: command.status)
            Text(command.status.badgeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(commandStatusTint(command.status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(commandStatusTint(command.status).opacity(0.12))
        )
    }

    private func commandStatusTint(
        _ status: SessionTranscriptCommandRunPresentation.Status
    ) -> Color {
        switch status.tone {
        case .running:
            return AppPalette.accent
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    @ViewBuilder
    private func statusDot(
        for status: SessionTranscriptCommandRunPresentation.Status
    ) -> some View {
        switch status.tone {
        case .running:
            LivePulseDot(size: 8)
        case .success, .failure:
            Circle()
                .fill(commandStatusTint(status))
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private func diffFileList(_ files: [SessionTranscriptDiffFilePresentation], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if !compact || index < 3 {
                    SessionSurfaceCard(
                        cornerRadius: 10,
                        fillColor: Color.clear,
                        strokeColor: AppPalette.chromeSurfaceStroke
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(file.path)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(AppPalette.primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(file.hunkCount == 1 ? "1 hunk" : "\(file.hunkCount) hunks")
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.secondaryText)
                            }

                            if compact {
                                Text(file.preview)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .lineLimit(3)
                            }

                            transcriptDiffHunks(file.hunks, compact: compact)
                        }
                        .padding(10)
                    }
                }
            }

            if compact && files.count > 3 {
                Text("+ \(files.count - 3) more files")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func transcriptDiffHunks(
        _ hunks: [SessionTranscriptDiffHunkPresentation],
        compact: Bool
    ) -> some View {
        let visibleHunks = compact ? Array(hunks.prefix(1)) : hunks

        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleHunks) { hunk in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunk.lines.enumerated()), id: \.element.id) { index, line in
                        if !compact || index < 12 {
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(diffForeground(for: line.kind))
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(diffBackground(for: line.kind))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if compact,
               let first = visibleHunks.first,
               first.lines.count > 12 {
                Text("+ \(first.lines.count - 12) more lines")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }

    private func diffForeground(for kind: SessionTranscriptDiffLinePresentation.Kind) -> Color {
        switch kind {
        case .added:
            return .green
        case .removed:
            return .red
        case .context, .meta:
            return AppPalette.primaryText
        }
    }

    private func diffBackground(for kind: SessionTranscriptDiffLinePresentation.Kind) -> Color {
        switch kind {
        case .added:
            return .green.opacity(0.14)
        case .removed:
            return .red.opacity(0.14)
        case .context:
            return Color.clear
        case .meta:
            return AppPalette.chromeSurface.opacity(0.75)
        }
    }
}

struct SessionTranscriptMonospaceBlock: View {
    let text: String
    let language: String?
    let accentColor: Color

    var body: some View {
        SessionSurfaceCard(
            cornerRadius: 12,
            fillColor: AppPalette.chromeSurface.opacity(0.9),
            strokeColor: AppPalette.chromeSurfaceStroke
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text.isEmpty ? " " : text)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppPalette.primaryText)
                        .lineSpacing(1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
    }
}
