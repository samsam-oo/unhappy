import SwiftUI
import CoreKit

@MainActor
public struct DirectSessionDetailView: View {
    private struct QuickSurface: Identifiable, Equatable {
        enum Kind: String {
            case info
            case files
            case review
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

    @StateObject private var viewModel: DirectSessionViewModel
    private let serverURLString: String
    private let token: String

    @State private var draftMessage = ""
    @State private var inspectedMessage: APISessionMessage?
    @State private var presentedQuickSurface: QuickSurface?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryCard
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                MessagesSectionRows(
                    isLoading: viewModel.isLoading,
                    errorMessage: viewModel.errorMessage,
                    visibleTranscriptPresentations: transcriptPresentations,
                    liveStatusText: nil,
                    transcriptBottomAnchorID: "__direct_session_bottom__",
                    onReferenceToggle: {},
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
                    Button("Tool Artifacts") {
                        presentedQuickSurface = QuickSurface(kind: .artifacts, filterPath: nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .background(Color.clear)
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
                        selectedReasoningLabel: selectedReasoningLabel
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
        .task {
            async let messageLoad: Void = viewModel.load(serverURLString: serverURLString, token: token)
            async let capabilitiesLoad: Void = viewModel.loadCapabilities(serverURLString: serverURLString, token: token)
            _ = await (messageLoad, capabilitiesLoad)
            viewModel.startPolling(serverURLString: serverURLString, token: token)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    private var providerLabel: String {
        viewModel.identity.provider.displayName
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

                if !viewModel.availableModelOptions.isEmpty || !viewModel.availableReasoningEfforts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !viewModel.availableModelOptions.isEmpty {
                            Menu {
                                Button("Use Session Model") {
                                    viewModel.selectedModelOverride = ""
                                }
                                ForEach(viewModel.availableModelOptions) { option in
                                    Button(option.menuLabel) {
                                        viewModel.selectedModelOverride = option.id
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Model")
                                    Spacer()
                                    Text(selectedModelLabel)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !viewModel.availableReasoningEfforts.isEmpty {
                            Menu {
                                Button("Use Session Default") {
                                    viewModel.selectedReasoningEffortOverride = .auto
                                }
                                ForEach(viewModel.availableReasoningEfforts, id: \.rawValue) { effort in
                                    Button(effort.displayName) {
                                        viewModel.selectedReasoningEffortOverride = effort
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Reasoning")
                                    Spacer()
                                    Text(selectedReasoningLabel)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let capabilitiesError = viewModel.capabilitiesErrorMessage, !capabilitiesError.isEmpty {
                            Text(capabilitiesError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var transcriptPresentations: [SessionTranscriptMessagePresentation] {
        viewModel.messages.map {
            SessionTranscriptPresentationBuilder.make(
                from: $0,
                dataEncryptionKey: nil
            )
        }
    }

    private var composerPlaceholder: String {
        "Message \(providerLabel)…"
    }

    private var selectedModelLabel: String {
        if let option = viewModel.selectedModelOption {
            return option.displayName
        }
        if let model = viewModel.identity.model, !model.isEmpty {
            return model
        }
        return "Session Default"
    }

    private var selectedReasoningLabel: String {
        if viewModel.selectedReasoningEffortOverride == .auto {
            return "Session Default"
        }
        return viewModel.selectedReasoningEffortOverride.displayName
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sendError = viewModel.sendErrorMessage, !sendError.isEmpty {
                Text(sendError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(composerPlaceholder, text: $draftMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)

                Button {
                    let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draftMessage = ""
                    Task {
                        let sent = await viewModel.sendMessage(
                            text,
                            serverURLString: serverURLString,
                            token: token
                        )
                        if !sent {
                            draftMessage = text
                        }
                    }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                }
                .disabled(viewModel.isSending || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppPalette.chromeSurfaceStroke.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct DirectSessionInfoView: View {
    let identity: DirectSessionIdentity
    let selectedModelLabel: String
    let selectedReasoningLabel: String

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
