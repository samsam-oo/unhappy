import SwiftUI
import CoreKit

struct MessagesSectionRows: View {
    let isLoading: Bool
    let errorMessage: String?
    let visibleTranscriptPresentations: [SessionTranscriptMessagePresentation]
    let liveStatusText: String?
    let transcriptBottomAnchorID: String
    let onReferenceToggle: () -> Void
    let onFileLinkTap: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        SessionListSectionBadgeRow(
            iconSystemName: "bubble.left.and.bubble.right.fill",
            title: "Messages"
        )
        .sessionListRow(insets: SessionListRowInsets.badge)

        if isLoading {
            TranscriptLoadingCard()
                .sessionListRow(insets: SessionListRowInsets.messageCard)
        } else if let errorMessage {
            TranscriptErrorCard(error: errorMessage, onRetry: onRetry)
                .sessionListRow(insets: SessionListRowInsets.messageCard)
        } else if visibleTranscriptPresentations.isEmpty {
            SessionSurfaceCard {
                Text("No synced messages yet for this session")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            }
            .sessionListRow(insets: SessionListRowInsets.messageCard)
        } else {
            ForEach(visibleTranscriptPresentations, id: \.messageID) { presentation in
                SessionTranscriptMessageRow(
                    presentation: presentation,
                    onReferenceToggle: onReferenceToggle,
                    onFileLinkTap: onFileLinkTap
                )
                .sessionListRow(insets: SessionListRowInsets.messageEntry)
            }
        }

        if let liveStatusText {
            SessionTranscriptLiveStatusRow(statusText: liveStatusText)
                .sessionListRow(insets: SessionListRowInsets.messageEntry)
        }

        Color.clear
            .frame(height: 1)
            .sessionListRow(insets: SessionListRowInsets.anchor)
            .id(transcriptBottomAnchorID)
    }
}

struct TranscriptLoadingCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(AppPalette.accent)
            Text("Loading messages…")
                .font(.footnote.monospaced())
                .foregroundStyle(AppPalette.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

struct TranscriptErrorCard: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text("Unable to load messages")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppPalette.primaryText)
            }

            Text(error)
                .font(.caption.monospaced())
                .foregroundStyle(AppPalette.secondaryText)
                .lineSpacing(1.5)

            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .modifier(DockChipModifier(tone: .neutral))
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

struct SessionTranscriptMessageRow: View {
    let presentation: SessionTranscriptMessagePresentation
    let onReferenceToggle: (() -> Void)?
    let onFileLinkTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: showsTimestamp ? 8 : 3) {
            if showsTimestamp {
                HStack {
                    Spacer()
                    Text(presentation.createdAtText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppPalette.secondaryText.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(presentation.entries) { entry in
                    SessionTranscriptLogLine(
                        entry: entry,
                        onReferenceToggle: onReferenceToggle,
                        onFileLinkTap: onFileLinkTap
                    )
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var showsTimestamp: Bool {
        presentation.entries.contains { entry in
            guard entry.role == .user || entry.role == .agent else { return false }
            return entry.kind == .text || entry.kind == .thinking
        }
    }
}

struct SessionTranscriptLiveStatusRow: View {
    let statusText: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            LivePulseDot(size: 7)
                .padding(.top, 4)
            LiveStatusShimmerText(
                text: statusText,
                lineLimit: 1
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveStatusShimmerText: View {
    let text: String
    let lineLimit: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AppPalette.secondaryText)
            .lineLimit(lineLimit)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let bandWidth = max(18, width * 0.24)
                        let highlightOpacity = colorScheme == .dark ? 0.40 : 0.34

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(highlightOpacity), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: bandWidth, height: proxy.size.height * 1.7)
                        .rotationEffect(.degrees(14))
                        .offset(
                            x: (phase * (width + bandWidth * 2)) - bandWidth,
                            y: -proxy.size.height * 0.35
                        )
                    }
                    .mask(
                        Text(text)
                            .font(.footnote)
                            .lineLimit(lineLimit)
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = 0
                        withAnimation(.linear(duration: 1.75).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
    }
}

struct SessionTranscriptLogLine: View {
    let entry: SessionTranscriptEntry
    let onReferenceToggle: (() -> Void)?
    let onFileLinkTap: (String) -> Void
    @State private var isExpanded = false

    var body: some View {
        if isSystemEvent {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                Text(systemEventText)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.chatToolBackground)
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        } else if isCollapsibleReferenceLogEntry {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    onReferenceToggle?()
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(AppPalette.terminalLineTool)
                            .padding(.top, 1)
                        Text(collapsibleTitle)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(AppPalette.terminalLineTool)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        SessionTranscriptToolRichContentView(entry: entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 1)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(AppPalette.terminalLineTool.opacity(0.45))
                            .frame(width: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isMainMessageEntry {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(roleColor)
                        .frame(width: 6, height: 6)
                    Text(roleLabel)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(roleColor)
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                SessionTranscriptMarkdownView(
                    markdown: entry.body,
                    role: entry.role,
                    kind: entry.kind,
                    onOpenFilePath: onFileLinkTap
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(roleColor.opacity(0.45))
                    .frame(width: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppPalette.terminalLineTool)
                }
                Text(entry.body)
                    .font(bodyFont)
                    .foregroundStyle(AppPalette.secondaryText)
                    .lineLimit(nil)
                    .lineSpacing(1.5)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private var isSystemEvent: Bool {
        entry.role == .system && entry.kind == .event
    }

    private var systemEventText: String {
        if let title = entry.title, !title.isEmpty {
            return "\(title): \(entry.body)"
        }
        return entry.body
    }

    private var bubbleColor: Color {
        if entry.role == .user {
            return AppPalette.chatUserBubble
        }
        return AppPalette.chatAgentBubble
    }

    private var roleLabel: String {
        entry.role == .user ? "user" : "assistant"
    }

    private var roleColor: Color {
        entry.role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent
    }

    private var isCollapsibleToolEntry: Bool {
        entry.kind == .toolCall || entry.kind == .toolResult || isEditFilesEntry
    }

    private var isCollapsibleReferenceLogEntry: Bool {
        isCollapsibleToolEntry || entry.kind == .raw
    }

    private var isMainMessageEntry: Bool {
        guard entry.role == .user || entry.role == .agent else { return false }
        switch entry.kind {
        case .text, .thinking:
            return true
        default:
            return false
        }
    }

    private var collapsibleTitle: String {
        if let summaryTitle = SessionTranscriptRichContentParser.summaryTitle(for: entry) {
            return summaryTitle
        }
        if isEditFilesEntry {
            return "Edit files"
        }
        if let title = entry.title, !title.isEmpty {
            return title
        }
        switch entry.kind {
        case .toolCall:
            return "Tool call"
        case .toolResult:
            return "Tool result"
        default:
            return "Details"
        }
    }

    private var isEditFilesEntry: Bool {
        let normalizedTitle = (entry.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedTitle.contains("edit files") {
            return true
        }

        let normalizedBody = entry.body.lowercased()
        return normalizedBody.contains("apply_patch") || normalizedBody.contains("*** begin patch")
    }

    private var bodyFont: Font {
        switch entry.kind {
        case .toolCall, .toolResult, .raw:
            return .footnote.monospaced()
        default:
            return .subheadline
        }
    }
}

struct LivePulseDot: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(AppPalette.liveActivity)
            .frame(width: size, height: size)
            .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.07 : 0.94))
            .opacity(reduceMotion ? 1 : (isAnimating ? 1 : 0.82))
            .shadow(
                color: AppPalette.liveActivity.opacity(reduceMotion ? 0.12 : (isAnimating ? 0.26 : 0.14)),
                radius: reduceMotion ? 0 : 4,
                y: 0
            )
            .overlay {
                Circle()
                    .stroke(AppPalette.liveActivity.opacity(0.55), lineWidth: 1)
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.32 : 1.0))
                    .opacity(reduceMotion ? 0.2 : (isAnimating ? 0.08 : 0.32))
            }
            .onAppear {
                guard !reduceMotion else {
                    isAnimating = false
                    return
                }
                isAnimating = false
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    isAnimating = false
                    return
                }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct SessionMessageDetailView: View {
    let presentation: SessionMessageDetailPresentation

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Sequence") {
                    Text(presentation.sequenceText)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Message ID") {
                    Text(presentation.id)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                }
                if let localID = presentation.localID {
                    LabeledContent("Local ID") {
                        Text(localID)
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                    }
                }
            }

            Section("Timestamps") {
                LabeledContent("Created") {
                    Text(presentation.createdAtText)
                }
                LabeledContent("Updated") {
                    Text(presentation.updatedAtText)
                }
            }

            Section("Content") {
                if let contentType = presentation.contentType {
                    LabeledContent("Type") {
                        Text(contentType)
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Payload Size") {
                        Text("\(presentation.payloadCharacterCount) chars")
                            .font(.footnote.monospaced())
                    }
                    if let payloadPreview = presentation.payloadPreview {
                        Text(payloadPreview)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                    if presentation.payloadTruncated {
                        Text("Payload preview is truncated to first \(SessionMessageDetailPresentationBuilder.payloadPreviewLimit) chars.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !presentation.payloadFields.isEmpty {
                        Divider()
                        Text("Parsed Fields")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(presentation.payloadFields) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(field.value)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(nil)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Text("No content payload")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
    }
}
