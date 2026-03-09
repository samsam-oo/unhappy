import SwiftUI
import CoreKit
import UIFoundation

@MainActor
public struct DirectSessionDetailView: View {
    private struct QuickSurface: Identifiable, Equatable {
        enum Kind: String {
            case info
            case files
            case review
            case worktree
            case artifacts
        }

        let kind: Kind
        let filterPath: String?

        var id: String {
            if let filterPath, !filterPath.isEmpty {
                return "\(kind.rawValue)|\(filterPath)"
            }
            return kind.rawValue
        }
    }

    private enum ComposerFocusField: Hashable {
        case message
        case customModel
    }

    @StateObject private var viewModel: DirectSessionViewModel
    private let serverURLString: String
    private let token: String

    @State private var draftMessage = ""
    @State private var queuedDraftMessages: [String] = []
    @State private var inspectedMessage: APISessionMessage?
    @State private var presentedQuickSurface: QuickSurface?
    @State private var isUsingCustomModelOverride = false
    @State private var customModelDraft = ""
    @State private var selectedPermissionModeOverride: APISessionMessagePermissionMode?
    @State private var showMissingDefaultsAlert = false
    @State private var cachedTranscriptPresentations: [SessionTranscriptMessagePresentation] = []
    @State private var shouldFollowTranscript = true
    @State private var transcriptBottomAnchorID = UUID().uuidString
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var compactTranscriptHorizontalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var regularTranscriptHorizontalPadding: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var transcriptTopSpacing: CGFloat = 12
    @FocusState private var focusedComposerField: ComposerFocusField?

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> DirectSessionViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    summaryCard
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    // Direct chat uses ScrollView, so transcript spacing has to be explicit here.
                    MessagesSectionRows(
                        isLoading: viewModel.isLoading,
                        errorMessage: viewModel.errorMessage,
                        visibleTranscriptPresentations: transcriptPresentations,
                        liveStatusText: nil,
                        transcriptBottomAnchorID: transcriptBottomAnchorID,
                        onReferenceToggle: {
                            shouldFollowTranscript = false
                        },
                        onFileLinkTap: { path in
                            viewModel.prepareFilePath(path)
                            presentedQuickSurface = QuickSurface(kind: .files, filterPath: path)
                        },
                        onMessageInspect: { messageID in
                            inspectedMessage = viewModel.messages.first(where: { $0.id == messageID })
                        },
                        onRetry: {
                            Task {
                                await viewModel.load(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                    )
                    .padding(.top, transcriptTopSpacing)
                    .padding(.horizontal, transcriptHorizontalPadding)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height > 0 {
                        shouldFollowTranscript = false
                    }
                }
            )
            .onChange(of: transcriptPresentations.map(\.messageID)) { _, _ in
                guard shouldFollowTranscript else { return }
                scrollTranscriptToBottom(using: proxy, animated: true)
            }
            .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
                guard wasLoading && !isLoading else { return }
                shouldFollowTranscript = true
                scrollTranscriptToBottom(using: proxy, animated: false)
            }
            .onAppear {
                scrollTranscriptToBottom(using: proxy, animated: false)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.identity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Session Info") {
                        presentedQuickSurface = QuickSurface(kind: .info, filterPath: nil)
                    }
                    Button("Files") {
                        presentedQuickSurface = QuickSurface(kind: .files, filterPath: nil)
                    }
                    Button("Review Diff") {
                        presentedQuickSurface = QuickSurface(kind: .review, filterPath: nil)
                    }
                    Button("Worktree") {
                        presentedQuickSurface = QuickSurface(kind: .worktree, filterPath: nil)
                    }
                    Button("Tool Artifacts") {
                        presentedQuickSurface = QuickSurface(kind: .artifacts, filterPath: nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if viewModel.identity.collabInProgressCount > 0 {
                    SessionSubAgentLiveBar(count: viewModel.identity.collabInProgressCount)
                }
                bottomDock
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
        }
        .sheet(item: $inspectedMessage) { message in
            NavigationStack {
                SessionMessageDetailView(
                    presentation: SessionMessageDetailPresentationBuilder.make(from: message)
                )
            }
        }
        .sheet(item: $presentedQuickSurface) { surface in
            NavigationStack {
                switch surface.kind {
                case .info:
                    DirectSessionInfoView(
                        identity: viewModel.identity,
                        selectedModelLabel: selectedModelLabel,
                        selectedReasoningLabel: selectedReasoningLabel,
                        selectedPermissionModeLabel: selectedPermissionModeLabel
                    )
                case .files:
                    DirectSessionFileView(
                        viewModel: viewModel,
                        transcriptPresentations: transcriptPresentations,
                        initialPath: surface.filterPath,
                        serverURLString: serverURLString,
                        token: token
                    )
                case .review:
                    DirectSessionReviewView(
                        viewModel: viewModel,
                        serverURLString: serverURLString,
                        token: token
                    )
                case .worktree:
                    DirectSessionWorktreeView(
                        viewModel: viewModel,
                        serverURLString: serverURLString,
                        token: token
                    )
                case .artifacts:
                    DirectSessionArtifactsView(
                        entries: surface.filterPath.map {
                            DirectSessionArtifacts.richEntries(
                                from: transcriptPresentations,
                                matchingFilePath: $0
                            )
                        } ?? DirectSessionArtifacts.richEntries(from: transcriptPresentations),
                        filterPath: surface.filterPath
                    )
                }
            }
        }
        .alert(
            "Set model and reasoning first",
            isPresented: $showMissingDefaultsAlert,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text("Pick a model and reasoning level in the bottom dock before sending a message.")
            }
        )
        .task {
            async let messageLoad: Void = viewModel.load(serverURLString: serverURLString, token: token)
            async let capabilitiesLoad: Void = viewModel.loadCapabilities(serverURLString: serverURLString, token: token)
            _ = await (messageLoad, capabilitiesLoad)
            refreshTranscriptPresentations()
            viewModel.startPolling(serverURLString: serverURLString, token: token)
        }
        .onChange(of: viewModel.selectedModelOverride) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                isUsingCustomModelOverride = false
                if customModelDraft == value {
                    customModelDraft = ""
                }
                return
            }
            if viewModel.availableModelOptions.contains(where: { $0.id == trimmed }) {
                isUsingCustomModelOverride = false
                return
            }
            isUsingCustomModelOverride = true
            customModelDraft = trimmed
        }
        .onChange(of: viewModel.messages) { _, _ in
            refreshTranscriptPresentations()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    private var providerLabel: String {
        viewModel.identity.provider.displayName
    }

    private var transcriptPresentations: [SessionTranscriptMessagePresentation] {
        cachedTranscriptPresentations
    }

    private var summaryCard: some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(providerLabel)
                        .modifier(DockChipModifier(tone: .primary))
                    Text(viewModel.identity.machineDisplayName)
                        .modifier(DockChipModifier(tone: .neutral))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.identity.cwd)
                        .font(.body.monospaced())
                        .foregroundStyle(AppPalette.primaryText)
                        .textSelection(.enabled)
                    if let model = viewModel.identity.model, !model.isEmpty {
                        Text(model)
                            .font(.footnote)
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }

                if let capabilitiesError = viewModel.capabilitiesErrorMessage, !capabilitiesError.isEmpty {
                    Text(capabilitiesError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private var composerPlaceholder: String {
        "Ask for follow-up changes"
    }

    private var selectedModelLabel: String {
        if isUsingCustomModelOverride {
            let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Custom" : trimmed
        }
        if let option = viewModel.selectedModelOption {
            return option.displayName
        }
        if let model = viewModel.identity.model, !model.isEmpty {
            return model
        }
        return "Model"
    }

    private var selectedReasoningLabel: String {
        if viewModel.selectedReasoningEffortOverride == .auto {
            return viewModel.identity.effort?.displayName ?? "Reasoning"
        }
        return viewModel.selectedReasoningEffortOverride.displayName
    }

    private var selectedPermissionModeLabel: String {
        DirectSessionPermissionModeAdapter.selectedLabel(
            provider: viewModel.identity.provider,
            override: selectedPermissionModeOverride,
            current: viewModel.identity.permissionMode
        )
    }

    private var trimmedDraftMessage: String {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canQueueDraft: Bool {
        !viewModel.isSending && !trimmedDraftMessage.isEmpty
    }

    private var transcriptHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular
            ? regularTranscriptHorizontalPadding
            : compactTranscriptHorizontalPadding
    }

    private var canSendDraft: Bool {
        !viewModel.isSending && (!trimmedDraftMessage.isEmpty || !queuedDraftMessages.isEmpty)
    }

    private var hasConfiguredModelAndReasoning: Bool {
        let hasModel = isUsingCustomModelOverride
            ? !customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : (
                !viewModel.selectedModelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(viewModel.identity.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            )

        let hasReasoning = viewModel.selectedReasoningEffortOverride != .auto || viewModel.identity.effort != nil
        return hasModel && hasReasoning
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            composerBar
            quickToolsBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.chromeSurfaceStroke.opacity(0.55), lineWidth: 1)
        )
        .shadow(
            color: AppPalette.chromeShadow.opacity(0.14),
            radius: 10,
            y: 3
        )
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !queuedDraftMessages.isEmpty {
                queuePreviewCard
            }

            if let sendError = viewModel.sendErrorMessage, !sendError.isEmpty {
                Text(sendError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                TextField(composerPlaceholder, text: $draftMessage, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .font(.subheadline.weight(.medium))
                    .focused($focusedComposerField, equals: .message)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.composerFieldBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focusedComposerField == .message
                            ? AppPalette.accent.opacity(0.55)
                            : AppPalette.composerFieldStroke.opacity(0.4),
                        lineWidth: focusedComposerField == .message ? 1.5 : 1
                    )
            }

            HStack(spacing: 8) {
                Button(action: queueCurrentDraft) {
                    Label("Queue", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppPalette.controlSurface)
                        )
                }
                .buttonStyle(PressableScaleButtonStyle())
                .disabled(!canQueueDraft)

                Button(action: sendCurrentOrQueuedDraft) {
                    Label(viewModel.isSending ? "Sending…" : "Send", systemImage: "paperplane.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppPalette.sendGradientTop,
                                            AppPalette.sendGradientBottom,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: AppPalette.accent.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(PressableScaleButtonStyle())
                .disabled(!canSendDraft)
                .opacity(hasConfiguredModelAndReasoning ? 1 : 0.58)
            }

            if isUsingCustomModelOverride {
                TextField("Custom model id", text: $customModelDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .focused($focusedComposerField, equals: .customModel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppPalette.controlSurface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                focusedComposerField == .customModel
                                    ? AppPalette.accent.opacity(0.55)
                                    : AppPalette.composerFieldStroke.opacity(0.4),
                                lineWidth: focusedComposerField == .customModel ? 1.5 : 1
                            )
                    }
            }
        }
    }

    private var queuePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let visibleQueuedMessages = Array(queuedDraftMessages.suffix(3))
            let hiddenCount = max(0, queuedDraftMessages.count - visibleQueuedMessages.count)
            let visibleStartIndex = max(0, queuedDraftMessages.count - visibleQueuedMessages.count)

            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
                Text("Steer Stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer(minLength: 0)
                Text(queuedDraftMessages.count == 1 ? "1 queued" : "\(queuedDraftMessages.count) queued")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
            }

            ForEach(Array(visibleQueuedMessages.enumerated()), id: \.offset) { index, text in
                let queueIndex = visibleStartIndex + index
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(AppPalette.secondaryText)
                    Text(text)
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(AppPalette.primaryText)
                    Spacer(minLength: 0)
                    Button("Edit") {
                        editQueuedDraft(at: queueIndex)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }

                if index < visibleQueuedMessages.count - 1 {
                    Rectangle()
                        .fill(AppPalette.chromeDivider.opacity(0.7))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.controlSurface.opacity(0.9))
        )
    }

    private var quickToolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                modelMenuButton
                if !viewModel.availableReasoningEfforts.isEmpty {
                    reasoningMenuButton
                }
                permissionModeMenuButton
                quickToolButton(title: "Info", systemImage: "info.circle", kind: .info)
                quickToolButton(title: "Files", systemImage: "doc.text", kind: .files)
                quickToolButton(title: "Diff", systemImage: "doc.text.magnifyingglass", kind: .review)
                quickToolButton(title: "Worktree", systemImage: "checkmark.circle", kind: .worktree)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private var modelMenuButton: some View {
        Menu {
            ForEach(viewModel.availableModelOptions) { option in
                Button(option.menuLabel) {
                    viewModel.selectedModelOverride = option.id
                    isUsingCustomModelOverride = false
                    customModelDraft = option.id
                }
            }
            Button("Custom model…") {
                isUsingCustomModelOverride = true
                if customModelDraft.isEmpty {
                    customModelDraft = viewModel.selectedModelOverride
                }
                focusedComposerField = .customModel
            }
        } label: {
            Label(selectedModelLabel, systemImage: "cpu")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var reasoningMenuButton: some View {
        Menu {
            ForEach(
                viewModel.availableReasoningEfforts.filter { $0 != .auto },
                id: \.rawValue
            ) { effort in
                Button(effort.displayName) {
                    viewModel.selectedReasoningEffortOverride = effort
                }
            }
        } label: {
            Label(selectedReasoningLabel, systemImage: "brain.head.profile")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var permissionModeMenuButton: some View {
        Menu {
            ForEach(
                DirectSessionPermissionModeAdapter.options(for: viewModel.identity.provider)
            ) { option in
                Button(option.label) {
                    selectedPermissionModeOverride = option.mode
                }
            }
        } label: {
            Label(selectedPermissionModeLabel, systemImage: "doc.badge.gearshape")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private func quickToolButton(title: String, systemImage: String, kind: QuickSurface.Kind) -> some View {
        Button {
            focusedComposerField = nil
            presentedQuickSurface = QuickSurface(kind: kind, filterPath: nil)
        } label: {
            Label(title, systemImage: systemImage)
                .modifier(DockChipModifier(tone: .neutral))
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private func queueCurrentDraft() {
        let text = trimmedDraftMessage
        guard !text.isEmpty else { return }
        queuedDraftMessages.append(text)
        draftMessage = ""
    }

    private func editQueuedDraft(at index: Int) {
        guard queuedDraftMessages.indices.contains(index) else { return }
        draftMessage = queuedDraftMessages.remove(at: index)
        focusedComposerField = .message
    }

    private func sendCurrentOrQueuedDraft() {
        guard hasConfiguredModelAndReasoning else {
            showMissingDefaultsAlert = true
            return
        }
        let currentDraft = trimmedDraftMessage
        let queuedDraft: String?
        if currentDraft.isEmpty {
            queuedDraft = queuedDraftMessages.isEmpty ? nil : queuedDraftMessages.removeFirst()
        } else {
            queuedDraft = nil
        }

        let outboundText = currentDraft.isEmpty ? queuedDraft : currentDraft
        guard let outboundText, !outboundText.isEmpty else { return }

        if !currentDraft.isEmpty {
            draftMessage = ""
        }
        focusedComposerField = nil

        if isUsingCustomModelOverride {
            viewModel.selectedModelOverride = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Task {
            let sent = await viewModel.sendMessage(
                outboundText,
                serverURLString: serverURLString,
                token: token,
                permissionMode: selectedPermissionModeOverride
            )
            if !sent {
                if currentDraft.isEmpty {
                    queuedDraftMessages.insert(outboundText, at: 0)
                } else {
                    draftMessage = outboundText
                }
            }
        }
    }

    private func refreshTranscriptPresentations() {
        let nextPresentations = viewModel.messages.map {
            SessionTranscriptPresentationBuilder.make(
                from: $0,
                dataEncryptionKey: nil
            )
        }
        guard cachedTranscriptPresentations != nextPresentations else { return }
        cachedTranscriptPresentations = nextPresentations
    }

    private func scrollTranscriptToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(transcriptBottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                action()
            }
        }
    }
}

private struct DirectSessionInfoView: View {
    let identity: DirectSessionIdentity
    let selectedModelLabel: String
    let selectedReasoningLabel: String
    let selectedPermissionModeLabel: String

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Provider") {
                    Text(identity.provider.displayName)
                }
                LabeledContent("Machine") {
                    Text(identity.machineDisplayName)
                }
                LabeledContent("Session ID") {
                    Text(identity.upstreamSessionID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Model") {
                    Text(selectedModelLabel)
                }
                LabeledContent("Reasoning") {
                    Text(selectedReasoningLabel)
                }
                LabeledContent("Permission") {
                    Text(selectedPermissionModeLabel)
                }
            }

            Section("Path") {
                Text(identity.cwd)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                if let transcriptPath = identity.transcriptPath, !transcriptPath.isEmpty {
                    Text(transcriptPath)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Session Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DirectSessionArtifactsView: View {
    let entries: [SessionTranscriptEntry]
    let filterPath: String?

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No tool artifacts yet",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Run a tool that produces command output or file changes to inspect it here.")
                )
            } else {
                ForEach(entries) { entry in
                    SessionTranscriptToolRichContentView(entry: entry)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(filterPath == nil ? "Artifacts" : "File Artifacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DirectSessionFileView: View {
    @ObservedObject var viewModel: DirectSessionViewModel
    let transcriptPresentations: [SessionTranscriptMessagePresentation]
    let initialPath: String?
    let serverURLString: String
    let token: String

    private var relatedEntries: [SessionTranscriptEntry] {
        let normalizedPath = viewModel.filePathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return [] }
        return DirectSessionArtifacts.richEntries(
            from: transcriptPresentations,
            matchingFilePath: normalizedPath
        )
    }

    var body: some View {
        List {
            Section("Path") {
                TextField("Project-relative or absolute path", text: $viewModel.filePathDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Load File") {
                    Task {
                        await viewModel.loadFile(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(
                    viewModel.isLoadingFile ||
                        viewModel.filePathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Section("Content") {
                if viewModel.isLoadingFile {
                    ProgressView("Loading file…")
                } else if let error = viewModel.fileErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if viewModel.fileContent.isEmpty {
                    Text("No file loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical) {
                        Text(viewModel.fileContent)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                }
            }

            Section("Related Artifacts") {
                if relatedEntries.isEmpty {
                    Text("No tool artifacts reference this file yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedEntries) { entry in
                        SessionTranscriptToolRichContentView(entry: entry)
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: initialPath ?? "") {
            guard let initialPath else { return }
            viewModel.prepareFilePath(initialPath)
            await viewModel.loadFile(
                serverURLString: serverURLString,
                token: token
            )
        }
    }
}

private struct DirectSessionReviewView: View {
    @ObservedObject var viewModel: DirectSessionViewModel
    let serverURLString: String
    let token: String

    private var reviewEntry: SessionTranscriptEntry? {
        let diffText = viewModel.reviewDiffOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diffText.isEmpty else { return nil }
        return SessionTranscriptEntry(
            id: "direct-review-diff",
            role: .agent,
            kind: .toolResult,
            title: "Review Diff",
            body: diffText,
            toolUseID: nil,
            sourceType: nil,
            toolName: nil,
            isSidechain: false,
            threadID: nil
        )
    }

    var body: some View {
        List {
            Section("Repository") {
                TextField("Repository path (optional)", text: $viewModel.reviewRepositoryPathDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("If empty, the current session directory is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(viewModel.isLoadingReview ? "Loading…" : "Load Review Diff") {
                    Task {
                        await viewModel.loadReview(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isLoadingReview)
            }

            if let status = viewModel.reviewStatusMessage, !status.isEmpty {
                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            if let error = viewModel.reviewErrorMessage, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Diff") {
                if viewModel.isLoadingReview {
                    ProgressView("Loading diff…")
                } else if let reviewEntry {
                    SessionTranscriptToolRichContentView(entry: reviewEntry)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                } else {
                    Text("No changes")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.reviewDiffOutput.isEmpty,
               viewModel.reviewStatusMessage == nil,
               viewModel.reviewErrorMessage == nil,
               !viewModel.isLoadingReview {
                await viewModel.loadReview(
                    serverURLString: serverURLString,
                    token: token
                )
            }
        }
    }
}

private struct DirectSessionWorktreeView: View {
    @ObservedObject var viewModel: DirectSessionViewModel
    let serverURLString: String
    let token: String

    var body: some View {
        List {
            Section("Actions") {
                Button(viewModel.isLoadingWorktree ? "Refreshing…" : "Refresh Worktree Status") {
                    Task {
                        await viewModel.loadWorktree(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isLoadingWorktree)
            }

            if let error = viewModel.worktreeErrorMessage, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let snapshot = viewModel.worktreeSnapshot {
                Section("Repository") {
                    LabeledContent("Root") {
                        Text(snapshot.repositoryRoot)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Branch") {
                        Text(snapshot.currentBranch)
                            .font(.footnote.monospaced())
                    }
                }

                Section("Worktrees") {
                    Text(snapshot.worktreeListOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                Section("Status") {
                    Text(snapshot.statusOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            } else if !viewModel.isLoadingWorktree {
                Section("Status") {
                    Text("No worktree details loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Worktree")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.worktreeSnapshot == nil,
               viewModel.worktreeErrorMessage == nil,
               !viewModel.isLoadingWorktree {
                await viewModel.loadWorktree(
                    serverURLString: serverURLString,
                    token: token
                )
            }
        }
    }
}
