import SwiftUI
import CoreKit
import FeatureSessionTools
import UIKit
import PhotosUI

@MainActor
public struct SessionDetailView: View {
    enum SessionQuickTool: String, Identifiable {
        case info
        case files
        case review
        case worktree

        var id: String { rawValue }
    }

    enum SessionComposerFlavor: String {
        case codex
        case claude
        case gemini
    }

    enum SessionComposerFocusField: Hashable {
        case message
        case customModel
    }

    struct CachedTranscriptPresentation: Equatable {
        let sourceMessage: APISessionMessage
        let dataEncryptionKey: String?
        let presentation: SessionTranscriptMessagePresentation
    }

    struct PendingPermissionRequest: Identifiable, Equatable {
        let id: String
        let callID: String
        let toolName: String
        let summary: String?
    }

    static let customModelOverrideOption = "__custom_model_override__"
    static let modelPickerDefaultOption = "__model_default__"
    static let modelPickerCustomOption = "__model_custom__"
    static let modelPickerPresetPrefix = "__model_preset__:"
    static let effortPickerCurrentOption = "__effort_current__"
    static let effortPickerPresetPrefix = "__effort_preset__:"
    static let permissionModePickerDefaultOption = "__permission_mode_default__"
    static let permissionModePickerPresetPrefix = "__permission_mode_preset__:"
    static let transcriptBottomAnchorID = "__session_transcript_bottom__"

    enum SessionComposerEffortSelection: String, CaseIterable, Identifiable {
        case low
        case medium
        case high
        case max
        case xhigh

        var id: String { rawValue }

        var label: String {
            switch self {
            case .low:
                return "Low"
            case .medium:
                return "Medium"
            case .high:
                return "High"
            case .max:
                return "Max"
            case .xhigh:
                return "XHigh"
            }
        }

        var overrideValue: SessionMessageEffortOverride {
            switch self {
            case .low:
                return .low
            case .medium:
                return .medium
            case .high:
                return .high
            case .max:
                return .max
            case .xhigh:
                return .xhigh
            }
        }
    }

    let session: APISession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let onClose: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("unhappy.native.showReasoningDetails")
    var showReasoningDetails = false
    @State var showArchiveConfirmation = false
    @State var showRenameSheet = false
    @State var renameDraft = ""
    @State var draftMessage = ""
    @State var presentedQuickTool: SessionQuickTool?
    @State var applyModelOverride = false
    @State var modelOverrideDraft = ""
    @State var selectedModelOverrideOption = ""
    @State var applyEffortOverride = false
    @State var selectedEffortOverride: SessionComposerEffortSelection = .medium
    @State var selectedPermissionModeOverride: APISessionMessagePermissionMode?
    @State var serverModelOverrideOptions: [String] = []
    @State var shouldFollowTranscript = true
    @State var scrollToBottomRequestID = UUID()
    @State var transcriptPresentationCache: [String: CachedTranscriptPresentation] = [:]
    @State var cachedVisibleTranscriptPresentations: [SessionTranscriptMessagePresentation] = []
    @State var linkedFilePathToOpen: String?
    @State var selectedImagePickerItems: [PhotosPickerItem] = []
    @State var draftImageAttachments: [SessionComposerImageAttachment] = []
    @State var respondingPermissionRequestID: String?
    @State var isRecoveringDisconnectedSession = false
    @State var permissionActionStatusMessage: String?
    @State var permissionActionErrorMessage: String?
    @GestureState var isInteractingWithBottomDock = false
    @FocusState var focusedComposerField: SessionComposerFocusField?

    public init(
        session: APISession,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        onClose: (() -> Void)? = nil,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.session = session
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.onClose = onClose
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
    }

    var tabBarVisibility: Visibility {
        UIDevice.current.userInterfaceIdiom == .pad ? .visible : .hidden
    }

    var canCloseDetailPane: Bool {
        onClose != nil
    }

    public var body: some View {
        ScrollViewReader { scrollProxy in
            decoratedSessionRoot(
                transcriptListContent(using: scrollProxy)
            )
        }
    }

    func transcriptListContent(using scrollProxy: ScrollViewProxy) -> some View {
        let messagesSectionRows = makeMessagesSectionRows()
        let listBase = transcriptListBase(messagesSectionRows: messagesSectionRows)
        return applyTranscriptLifecycleHandlers(to: listBase, using: scrollProxy)
    }

    func makeMessagesSectionRows() -> MessagesSectionRows {
        MessagesSectionRows(
            isLoading: viewModel.isLoadingSessionMessages,
            errorMessage: viewModel.selectedSessionErrorMessage,
            visibleTranscriptPresentations: visibleTranscriptPresentations,
            liveStatusText: liveStatusText,
            transcriptBottomAnchorID: Self.transcriptBottomAnchorID,
            onReferenceToggle: {
                shouldFollowTranscript = false
            },
            onFileLinkTap: { path in
                shouldFollowTranscript = false
                linkedFilePathToOpen = path
                presentedQuickTool = .files
            },
            onRetry: {
                Task {
                    await viewModel.loadMessages(
                        for: session.id,
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
        )
    }

    func transcriptListBase(messagesSectionRows: MessagesSectionRows) -> some View {
        List {
            Section {
                sessionSectionContent
            }

            Section {
                messagesSectionRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(transcriptBackground)
        .scrollDismissesKeyboard(.immediately)
        .scrollDisabled(isInteractingWithBottomDock)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedComposerField = nil
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { value in
                // Only treat mostly-vertical drags as transcript scrolling.
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                focusedComposerField = nil
                guard shouldFollowTranscript else { return }
                shouldFollowTranscript = false
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard canCloseDetailPane else { return }
                guard value.startLocation.x <= 40 else { return }
                guard value.translation.width > 90 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                onClose?()
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomInsetContent
        }
        // Keep auto-follow behavior via explicit scroll requests below.
        // Avoid defaultScrollAnchor on List because rapid shrink/grow updates can trigger
        // UICollectionView target index assertions on some iOS versions.
        .toolbar(tabBarVisibility, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if canCloseDetailPane {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose?()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                topBarTitleView
            }
            ToolbarItem(placement: .topBarTrailing) {
                toolbarTrailingContent
            }
        }
    }

    func applyTranscriptLifecycleHandlers<Content: View>(
        to content: Content,
        using scrollProxy: ScrollViewProxy
    ) -> some View {
        let appearanceHandled = applyTranscriptAppearanceHandlers(
            to: content,
            using: scrollProxy
        )
        return applyTranscriptStateChangeHandlers(
            to: appearanceHandled,
            using: scrollProxy
        )
    }

    func applyTranscriptAppearanceHandlers<Content: View>(
        to content: Content,
        using scrollProxy: ScrollViewProxy
    ) -> some View {
        content
            .onAppear {
                handleTranscriptOnAppear(using: scrollProxy)
            }
            .onDisappear {
                viewModel.stopSelectedSessionMessagesPolling()
                viewModel.clearDetailSelectionIfNeeded(sessionID: session.id)
            }
    }

    func applyTranscriptStateChangeHandlers<Content: View>(
        to content: Content,
        using scrollProxy: ScrollViewProxy
    ) -> some View {
        let cacheHandled = applyTranscriptCacheChangeHandlers(
            to: content,
            using: scrollProxy
        )
        return applyTranscriptScrollChangeHandlers(
            to: cacheHandled,
            using: scrollProxy
        )
    }

    func applyTranscriptCacheChangeHandlers<Content: View>(
        to content: Content,
        using scrollProxy: ScrollViewProxy
    ) -> some View {
        content
            .onChange(of: viewModel.selectedSessionMessages) { _, messages in
                handleSelectedSessionMessagesChange(messages)
            }
            .onChange(of: currentSession.dataEncryptionKey) { _, _ in
                refreshTranscriptPresentationCacheForCurrentState()
            }
            .onChange(of: visibleTranscriptMessageIDs) { oldIDs, newIDs in
                handleVisibleTranscriptMessageIDsChange(
                    oldIDs: oldIDs,
                    newIDs: newIDs,
                    using: scrollProxy
                )
            }
    }

    func applyTranscriptScrollChangeHandlers<Content: View>(
        to content: Content,
        using scrollProxy: ScrollViewProxy
    ) -> some View {
        content
            .onChange(of: scrollToBottomRequestID) { _, _ in
                scrollTranscriptToBottom(using: scrollProxy)
            }
            .onChange(of: focusedComposerField) { _, focusedField in
                handleFocusedComposerFieldChange(
                    focusedField,
                    using: scrollProxy
                )
            }
            .onChange(of: viewModel.isLoadingSessionMessages) { wasLoading, isLoading in
                handleLoadingSessionMessagesChange(
                    wasLoading: wasLoading,
                    isLoading: isLoading,
                    using: scrollProxy
                )
            }
    }

    func handleSelectedSessionMessagesChange(_ messages: [APISessionMessage]) {
        refreshTranscriptPresentationCache(
            messages: messages,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    func handleFocusedComposerFieldChange(
        _ focusedField: SessionComposerFocusField?,
        using scrollProxy: ScrollViewProxy
    ) {
        guard focusedField != nil else { return }
        shouldFollowTranscript = true
        scrollTranscriptToBottom(using: scrollProxy)
    }

    func handleLoadingSessionMessagesChange(
        wasLoading: Bool,
        isLoading: Bool,
        using scrollProxy: ScrollViewProxy
    ) {
        guard wasLoading && !isLoading else { return }
        shouldFollowTranscript = true
        scrollTranscriptToBottom(using: scrollProxy, animated: false)
    }

    func handleTranscriptOnAppear(using scrollProxy: ScrollViewProxy) {
        if !availableEffortSelections.contains(selectedEffortOverride),
           let first = availableEffortSelections.first {
            selectedEffortOverride = first
        }
        if serverModelOverrideOptions.isEmpty {
            Task {
                await loadServerModelOptions()
            }
        }
        viewModel.startSelectedSessionMessagesPolling(
            for: session.id,
            serverURLString: serverURLString,
            token: token
        )
        refreshTranscriptPresentationCacheForCurrentState()
        scrollTranscriptToBottom(using: scrollProxy, animated: false)
    }

    func decoratedSessionRoot<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showRenameSheet) {
                renameSessionSheet
            }
            .sheet(item: $presentedQuickTool) { tool in
                quickToolSheet(for: tool)
            }
            .onChange(of: selectedImagePickerItems) { _, items in
                handleSelectedImagePickerItemsChange(items)
            }
            .alert(
                "Archive session?",
                isPresented: $showArchiveConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Archive", role: .destructive) {
                        Task {
                            await viewModel.deleteSession(
                                sessionID: currentSession.id,
                                serverURLString: serverURLString,
                                token: token
                            )
                            if !viewModel.sessions.contains(where: { $0.id == currentSession.id }) {
                                dismiss()
                            }
                        }
                    }
                }
            )
    }

    var renameSessionSheet: some View {
        SessionRenameSheet(
            isPresented: $showRenameSheet,
            renameDraft: $renameDraft,
            isRenaming: viewModel.isRenaming(sessionID: session.id),
            onSave: { nextTitle in
                Task {
                    await viewModel.setSessionTitle(
                        sessionID: currentSession.id,
                        title: nextTitle.isEmpty ? nil : nextTitle,
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
        )
    }

    func quickToolSheet(for tool: SessionQuickTool) -> some View {
        NavigationStack {
            quickToolDestinationView(tool)
                .toolbar {
                    if tool == .files, canCloseDetailPane {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                onClose?()
                                presentedQuickTool = nil
                                linkedFilePathToOpen = nil
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            presentedQuickTool = nil
                            if tool == .files {
                                linkedFilePathToOpen = nil
                            }
                        }
                    }
                }
        }
    }
}
