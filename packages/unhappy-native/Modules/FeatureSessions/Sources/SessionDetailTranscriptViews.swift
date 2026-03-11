import SwiftUI
import UIKit
import CoreKit
import UIFoundation

let directSessionTranscriptScrollCoordinateSpace = "direct-session-transcript-scroll"

struct DirectSessionTranscriptViewportHeightPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DirectSessionTranscriptBottomAnchorMinYPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum SessionTranscriptLogLineDisplayMode: Equatable {
    case systemEvent
    case collapsibleReference
    case mainMessage
    case plainText

    static func resolve(for entry: SessionTranscriptEntry) -> Self {
        if entry.role == .system && entry.kind == .event {
            return .systemEvent
        }

        if SessionTranscriptRichContentParser.userInputPresentation(for: entry) != nil {
            return .mainMessage
        }

        if entry.kind == .toolCall || entry.kind == .toolResult || entry.kind == .raw || isEditFilesEntry(entry) {
            return .collapsibleReference
        }

        if (entry.role == .user || entry.role == .agent) &&
            (entry.kind == .text || entry.kind == .thinking) {
            return .mainMessage
        }

        return .plainText
    }

    static func isEditFilesEntry(_ entry: SessionTranscriptEntry) -> Bool {
        let normalizedTitle = (entry.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedTitle.contains("edit files") {
            return true
        }

        let normalizedBody = entry.body.lowercased()
        return normalizedBody.contains("apply_patch") || normalizedBody.contains("*** begin patch")
    }
}

struct MessagesSectionRows: View {
    let isLoading: Bool
    let errorMessage: String?
    let visibleTranscriptPresentations: [SessionTranscriptMessagePresentation]
    let liveStatusText: String?
    let transcriptBottomAnchorID: String
    let onReferenceToggle: () -> Void
    let onFileLinkTap: (String) -> Void
    let onMessageInspect: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .sessionListRow(insets: SessionListRowInsets.messageCard)
        } else {
            ForEach(visibleTranscriptPresentations, id: \.messageID) { presentation in
                SessionTranscriptMessageRow(
                    presentation: presentation,
                    onReferenceToggle: onReferenceToggle,
                    onFileLinkTap: onFileLinkTap,
                    onMessageInspect: {
                        onMessageInspect(presentation.messageID)
                    }
                )
                .id(presentation.messageID)
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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DirectSessionTranscriptBottomAnchorMinYPreferenceKey.self,
                        value: proxy.frame(in: .named(directSessionTranscriptScrollCoordinateSpace)).minY
                    )
                }
            )
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
    let onMessageInspect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: showsTimestamp ? 6 : 2) {
            if showsTimestamp {
                HStack {
                    Spacer()
                    Text(presentation.createdAtText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppPalette.secondaryText.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(presentation.entries) { entry in
                    SessionTranscriptLogLine(
                        entry: entry,
                        onReferenceToggle: onReferenceToggle,
                        onFileLinkTap: onFileLinkTap
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 0)
        .contextMenu {
            Button("Copy Message") {
                UIPasteboard.general.string = copyableText
            }
            if let onMessageInspect {
                Button("Inspect Message") {
                    onMessageInspect()
                }
            }
        }
    }

    private var showsTimestamp: Bool {
        presentation.entries.contains { entry in
            SessionTranscriptLogLineDisplayMode.resolve(for: entry) == .mainMessage
        }
    }

    private var copyableText: String {
        presentation.entries
            .compactMap { entry -> String? in
                if let userInput = SessionTranscriptRichContentParser.userInputPresentation(for: entry),
                   let body = userInput.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !body.isEmpty {
                    return body
                }

                let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty, !body.isEmpty {
                    return title + "\n" + body
                }
                if let title, !title.isEmpty {
                    return title
                }
                return body.isEmpty ? nil : body
            }
            .joined(separator: "\n\n")
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

    private var displayMode: SessionTranscriptLogLineDisplayMode {
        SessionTranscriptLogLineDisplayMode.resolve(for: entry)
    }

    private var userInputPresentation: SessionTranscriptGenericToolPresentation? {
        SessionTranscriptRichContentParser.userInputPresentation(for: entry)
    }

    var body: some View {
        if displayMode == .systemEvent {
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
        } else if displayMode == .collapsibleReference {
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
                        Image(systemName: collapsibleSymbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.accent)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collapsibleTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.primaryText)
                                .lineLimit(1)
                            if let collapsibleSubtitle, !collapsibleSubtitle.isEmpty {
                                Text(collapsibleSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .lineLimit(1)
                            }
                        }
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
            .padding(.vertical, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if displayMode == .mainMessage {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(roleColor)
                        .frame(width: 6, height: 6)
                    Text(roleLabel)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(roleColor)
                    if let title = mainMessageTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                if userInputPresentation == nil,
                   let attachmentDataURL = entry.attachmentDataURL {
                    SessionTranscriptInlineImageView(
                        source: attachmentDataURL,
                        altText: imageAltText
                    )
                }

                if shouldRenderMessageBody,
                   !mainMessageBody.isEmpty {
                    SessionTranscriptMarkdownView(
                        markdown: mainMessageBody,
                        role: messageRole,
                        kind: entry.kind,
                        onOpenFilePath: onFileLinkTap
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
            .padding(.vertical, 0)
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
        switch messageRole {
        case .user:
            return "user"
        case .agent:
            return "assistant"
        case .system:
            return "system"
        }
    }

    private var roleColor: Color {
        switch messageRole {
        case .user:
            return AppPalette.terminalLineUser
        case .agent:
            return AppPalette.terminalLineAgent
        case .system:
            return AppPalette.secondaryText
        }
    }

    private var messageRole: SessionTranscriptEntryRole {
        userInputPresentation == nil ? entry.role : .user
    }

    private var mainMessageTitle: String? {
        if let userInputPresentation,
           let target = userInputPresentation.compactSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            return "to \(target)"
        }
        return entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mainMessageBody: String {
        if let userInputPresentation,
           let body = userInputPresentation.body?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return body
        }
        return entry.body
    }

    private var collapsibleTitle: String {
        if let summaryTitle = SessionTranscriptRichContentParser.summaryTitle(for: entry) {
            return summaryTitle
        }
        if SessionTranscriptLogLineDisplayMode.isEditFilesEntry(entry) {
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

    private var collapsibleSubtitle: String? {
        SessionTranscriptRichContentParser.summarySubtitle(for: entry)
    }

    private var collapsibleSymbolName: String {
        if let richContent = SessionTranscriptRichContentParser.richToolContent(for: entry) {
            switch richContent {
            case .commandExecution:
                return "terminal"
            case .fileChanges:
                return "square.and.pencil"
            case .diff:
                return "arrow.left.arrow.right"
            case .toolDetails(let tool):
                switch tool.kind {
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
        }

        if SessionTranscriptLogLineDisplayMode.isEditFilesEntry(entry) {
            return "square.and.pencil"
        }

        switch entry.kind {
        case .toolResult:
            return "checkmark.circle"
        case .toolCall:
            return "hammer"
        case .raw:
            return "doc.text"
        case .text, .thinking, .event:
            return "doc.text"
        }
    }

    private var bodyFont: Font {
        switch entry.kind {
        case .toolCall, .toolResult, .raw:
            return .footnote.monospaced()
        default:
            return .subheadline
        }
    }

    private var shouldRenderMessageBody: Bool {
        if userInputPresentation != nil {
            return true
        }
        guard entry.attachmentDataURL != nil else { return true }
        return entry.body != imageAltText
    }

    private var imageAltText: String {
        let trimmed = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Image" : trimmed
    }
}

struct SessionTranscriptInlineImageView: View {
    let source: String
    let altText: String

    private var image: UIImage? {
        Self.resolveImage(from: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppPalette.chromeSurfaceStroke, lineWidth: 1)
                    }
                    .frame(maxWidth: min(UIScreen.main.bounds.width * 0.72, 320), maxHeight: 240, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .foregroundStyle(AppPalette.secondaryText)
                    Text(altText)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.chatToolBackground)
                )
            }

            if !altText.isEmpty {
                Text(altText)
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }

    private static func resolveImage(from source: String) -> UIImage? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("data:image/"),
           let commaIndex = trimmed.firstIndex(of: ",") {
            let encoded = String(trimmed[trimmed.index(after: commaIndex)...])
            if let data = decodeBase64(encoded) {
                return UIImage(data: data)
            }
        }

        if trimmed.hasPrefix("file://"),
           let url = URL(string: trimmed) {
            return UIImage(contentsOfFile: url.path)
        }

        if trimmed.hasPrefix("/") {
            return UIImage(contentsOfFile: trimmed)
        }

        return nil
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        if let direct = Data(base64Encoded: raw) {
            return direct
        }
        let replaced = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - (replaced.count % 4)) % 4
        let padded = replaced + String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: padded)
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

            if !presentation.parsedEntries.isEmpty {
                Section("Parsed Transcript") {
                    ForEach(presentation.parsedEntries) { entry in
                        SessionMessageDetailEntryView(entry: entry)
                            .listRowSeparator(.hidden)
                    }
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

private struct SessionMessageDetailEntryView: View {
    let entry: SessionTranscriptEntry

    var body: some View {
        if SessionTranscriptRichContentParser.richToolContent(for: entry) != nil {
            SessionTranscriptToolRichContentView(entry: entry)
                .padding(.vertical, 4)
        } else {
            SessionSurfaceCard(
                cornerRadius: 14,
                fillColor: entry.role == .user
                    ? AppPalette.chatUserBubble.opacity(0.96)
                    : AppPalette.chatAgentBubble.opacity(0.96),
                strokeColor: strokeColor
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(roleColor)
                            .frame(width: 7, height: 7)
                        Text(roleLabel)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(roleColor)
                        if let title = entry.title, !title.isEmpty {
                            Text(title)
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppPalette.secondaryText)
                                .lineLimit(1)
                        }
                        if entry.isSidechain {
                            Text("Collab")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppPalette.liveActivity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppPalette.liveActivityMuted)
                                )
                        }
                        Spacer(minLength: 0)
                    }

                    if usesMarkdownBody {
                        SessionTranscriptMarkdownView(
                            markdown: entry.body,
                            role: entry.role,
                            kind: entry.kind,
                            onOpenFilePath: { _ in }
                        )
                    } else {
                        SessionTranscriptMonospaceBlock(
                            text: entry.body,
                            language: monospaceLanguage,
                            accentColor: roleColor
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private var usesMarkdownBody: Bool {
        switch entry.kind {
        case .text, .thinking, .event:
            return true
        case .toolCall, .toolResult, .raw:
            return false
        }
    }

    private var monospaceLanguage: String? {
        switch entry.kind {
        case .toolCall:
            return "json"
        case .toolResult, .raw, .text, .thinking, .event:
            return nil
        }
    }

    private var roleLabel: String {
        switch entry.role {
        case .user:
            return "user"
        case .agent:
            return "assistant"
        case .system:
            return "system"
        }
    }

    private var roleColor: Color {
        switch entry.role {
        case .user:
            return AppPalette.terminalLineUser
        case .agent:
            return AppPalette.terminalLineAgent
        case .system:
            return AppPalette.secondaryText
        }
    }

    private var strokeColor: Color {
        if entry.isSidechain {
            return AppPalette.liveActivity.opacity(0.28)
        }
        return roleColor.opacity(0.18)
    }
}
