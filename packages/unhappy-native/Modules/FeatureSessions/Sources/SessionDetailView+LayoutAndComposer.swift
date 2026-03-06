import SwiftUI
import CoreKit
import FeatureSessionTools
import PhotosUI
import UniformTypeIdentifiers

extension SessionDetailView {
    var sessionSectionContent: some View {
        SessionSummarySectionRows(
            title: currentSessionTitle,
            titleIsPrimary: currentSessionHasDisplayTitle,
            sessionID: currentSession.id,
            statusText: currentSession.active ? "Active" : "Inactive",
            isActive: currentSession.active,
            updatedText: SessionTimestampPresentation.updatedLabel(for: currentSession.updatedAt)
        )
    }

    var approvalBottomSheet: some View {
        SessionApprovalBottomSheet(
            requests: approvalRequestRowModels,
            respondingRequestID: respondingPermissionRequestID,
            isRecoveringDisconnectedSession: isRecoveringDisconnectedSession,
            statusMessage: permissionActionStatusMessage,
            errorMessage: permissionActionErrorMessage,
            surfaceColor: bottomSheetSurfaceColor,
            shadowColor: AppPalette.chromeShadow.opacity(colorScheme == .dark ? 0.36 : 0.10),
            onApprove: { requestID in
                respondToPermissionRequest(requestID, approved: true)
            },
            onDeny: { requestID in
                respondToPermissionRequest(requestID, approved: false)
            }
        )
    }

    var approvalRequestRowModels: [SessionApprovalRequestRowModel] {
        pendingPermissionRequests.map { request in
            SessionApprovalRequestRowModel(
                id: request.id,
                callID: request.callID,
                toolName: request.toolName,
                summary: request.summary
            )
        }
    }

    var transcriptBackground: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppPalette.accent.opacity(colorScheme == .dark ? 0.06 : 0.07))
                .frame(width: 320, height: 320)
                .blur(radius: 56)
                .offset(x: 160, y: -260)
        }
        .ignoresSafeArea()
    }

    var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.14),
                Color(red: 0.06, green: 0.07, blue: 0.10),
            ]
        }

        return [
            AppPalette.chatBackgroundTop,
            AppPalette.chatBackgroundBottom,
        ]
    }

    var isKeyboardActive: Bool {
        focusedComposerField != nil
    }

    var bottomSheetSurfaceColor: Color {
        Color(.systemBackground)
    }

    var bottomSheetCornerRadius: CGFloat {
        22
    }

    var bottomDock: some View {
        VStack(spacing: isKeyboardActive ? 6 : 10) {
            composerBar
            quickToolsBar
        }
        .padding(.horizontal, 12)
        .padding(.top, isKeyboardActive ? 8 : 10)
        .padding(.bottom, isKeyboardActive ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: bottomSheetCornerRadius, style: .continuous)
                .fill(bottomSheetSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: bottomSheetCornerRadius, style: .continuous)
                .stroke(
                    AppPalette.chromeSurfaceStroke.opacity(isKeyboardActive ? 0.32 : 0.55),
                    lineWidth: 1
                )
        )
        .shadow(
            color: AppPalette.chromeShadow.opacity(colorScheme == .dark ? 0.42 : 0.14),
            radius: isKeyboardActive ? 8 : 10,
            y: isKeyboardActive ? 2 : 3
        )
        .animation(.easeInOut(duration: 0.18), value: isKeyboardActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($isInteractingWithBottomDock) { _, state, _ in
                state = true
            }
        )
    }

    var bottomInsetContent: some View {
        VStack(spacing: isKeyboardActive ? 6 : 8) {
            if subAgentInProgressCount > 0 {
                SessionSubAgentLiveBar(count: subAgentInProgressCount)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !pendingPermissionRequests.isEmpty {
                approvalBottomSheet
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            bottomDock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, isKeyboardActive ? 6 : 8)
        .animation(.easeInOut(duration: 0.2), value: subAgentInProgressCount > 0)
        .animation(.easeInOut(duration: 0.2), value: pendingPermissionRequests.count)
        .animation(.easeInOut(duration: 0.18), value: isKeyboardActive)
    }

    var topBarTitleView: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            Text(currentSessionTitle)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(AppPalette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    var toolbarTrailingContent: some View {
        SessionToolbarTrailingMenu(
            isBusy: viewModel.isDeleting(sessionID: session.id) || viewModel.isRenaming(sessionID: session.id),
            onListCodexSessions: {
                showCodexThreadsSheet = true
                if codexResumeDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    codexResumeDirectoryDraft = codexCwdFilterDraft
                }
                Task {
                    await viewModel.loadCodexThreads(
                        for: session.id,
                        serverURLString: serverURLString,
                        token: token,
                        cwd: normalizedCWD(from: codexCwdFilterDraft)
                    )
                }
            },
            onListClaudeSessions: {
                showClaudeSessionsSheet = true
                if claudeResumeDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    claudeResumeDirectoryDraft = claudeCwdFilterDraft
                }
                Task {
                    await viewModel.loadClaudeSessions(
                        for: session.id,
                        serverURLString: serverURLString,
                        token: token,
                        cwd: normalizedCWD(from: claudeCwdFilterDraft)
                    )
                }
            },
            onRename: {
                renameDraft = currentSession.displayName ?? ""
                showRenameSheet = true
            },
            onDelete: {
                showDeleteConfirmation = true
            }
        )
    }

    var composerBar: some View {
        SessionComposerInputPanel(
            isKeyboardActive: isKeyboardActive,
            colorScheme: colorScheme,
            isSending: viewModel.isSendingMessage(sessionID: session.id),
            queuedComposerMessages: viewModel.queuedComposerMessages(for: currentSession.id),
            applyModelOverride: applyModelOverride,
            selectedModelOverrideOption: selectedModelOverrideOption,
            customModelOverrideOption: Self.customModelOverrideOption,
            sendErrorMessage: viewModel.sendMessageErrorMessage,
            supportsImageAttachments: parsedSessionFlavor == .codex,
            imageAttachments: draftImageAttachments,
            photoPickerSelection: $selectedImagePickerItems,
            focusedComposerField: $focusedComposerField,
            draftMessage: $draftMessage,
            modelOverrideDraft: $modelOverrideDraft,
            onQueue: {
                submitDraftMessage(with: .queue)
            },
            onSend: {
                submitDraftMessage(with: .immediate)
            },
            onRemoveImageAttachment: { attachmentID in
                draftImageAttachments.removeAll { $0.id == attachmentID }
            },
            onEditQueuedMessage: { queueIndex, fallbackText in
                let restored = viewModel.takeQueuedComposerMessage(
                    for: currentSession.id,
                    at: queueIndex
                ) ?? fallbackText
                draftMessage = restored
                focusedComposerField = .message
            }
        )
    }

    func submitDraftMessage(with steerMode: APISessionSteerMode) {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImageAttachments.isEmpty else { return }
        focusedComposerField = nil

        let modelOverride: SessionMessageModelOverride
        if applyModelOverride {
            switch selectedModelOverrideOption {
            case Self.customModelOverrideOption:
                let normalized = modelOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                modelOverride = normalized.isEmpty ? .reset : .set(normalized)
            case "":
                modelOverride = .reset
            default:
                modelOverride = .set(selectedModelOverrideOption)
            }
        } else {
            modelOverride = .inherit
        }

        let effortOverride: SessionMessageEffortOverride
        if applyEffortOverride && supportsReasoningEffortOverride {
            effortOverride = selectedEffortOverride.overrideValue
        } else {
            effortOverride = .inherit
        }

        Task {
            let sent = await viewModel.sendMessage(
                for: session.id,
                text: text,
                attachments: draftImageAttachments,
                steerMode: steerMode,
                permissionMode: selectedPermissionModeOverride,
                modelOverride: modelOverride,
                effortOverride: effortOverride,
                serverURLString: serverURLString,
                token: token
            )
            if sent {
                shouldFollowTranscript = true
                scrollToBottomRequestID = UUID()
                draftMessage = ""
                draftImageAttachments = []
                selectedImagePickerItems = []
            }
        }
    }

    func handleSelectedImagePickerItemsChange(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var nextAttachments = draftImageAttachments
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    continue
                }
                let mimeType = mimeType(for: item, data: data)
                let candidate = SessionComposerImageAttachment(data: data, mimeType: mimeType)
                if nextAttachments.contains(where: { $0.data == candidate.data && $0.mimeType == candidate.mimeType }) {
                    continue
                }
                nextAttachments.append(candidate)
            }
            draftImageAttachments = nextAttachments
            selectedImagePickerItems = []
        }
    }

    func mimeType(for item: PhotosPickerItem, data: Data) -> String {
        if let type = item.supportedContentTypes.first {
            if type.conforms(to: .png) {
                return "image/png"
            }
            if type.conforms(to: .gif) {
                return "image/gif"
            }
            if type.conforms(to: .heic) || type.conforms(to: .heif) {
                return "image/heic"
            }
            if type.conforms(to: .webP) {
                return "image/webp"
            }
            if type.conforms(to: .jpeg) {
                return "image/jpeg"
            }
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0x47, 0x49, 0x46]) {
            return "image/gif"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        return "image/jpeg"
    }

    var supportsReasoningEffortOverride: Bool {
        guard let flavor = parsedSessionFlavor else { return false }
        switch flavor {
        case .codex, .claude:
            return true
        case .gemini:
            return false
        }
    }

    var availableEffortSelections: [SessionComposerEffortSelection] {
        guard let flavor = parsedSessionFlavor else {
            return [.auto, .low, .medium, .high]
        }
        switch flavor {
        case .codex:
            return [.auto, .low, .medium, .high, .xhigh]
        case .claude:
            return [.auto, .low, .medium, .high, .max]
        case .gemini:
            return [.auto]
        }
    }

    var availableModelOverrideOptions: [String] {
        if !serverModelOverrideOptions.isEmpty {
            return serverModelOverrideOptions
        }
        guard let flavor = parsedSessionFlavor else { return [] }
        switch flavor {
        case .codex:
            return [
                "gpt-5.3-codex",
                "gpt-5.2-codex",
                "gpt-5-codex",
                "gpt-5",
            ]
        case .claude:
            return [
                "claude-opus-4-6",
                "claude-sonnet-4-5",
                "claude-haiku-4-5",
            ]
        case .gemini:
            return [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
            ]
        }
    }

    var quickToolsBar: some View {
        SessionQuickToolsDockBar(
            supportsReasoningEffortOverride: supportsReasoningEffortOverride,
            selectedModelOverrideLabel: selectedModelOverrideLabel,
            selectedReasoningOverrideLabel: selectedReasoningOverrideLabel,
            selectedFileModeLabel: selectedFileModeLabel,
            modelPickerOptions: modelPickerOptions,
            effortPickerOptions: effortPickerOptions,
            permissionModePickerOptions: permissionModePickerOptions,
            modelPickerSelection: modelPickerSelection,
            effortPickerSelection: effortPickerSelection,
            permissionModePickerSelection: permissionModePickerSelection,
            sessionIdentity: "\(session.id)-\(supportsReasoningEffortOverride)-\(serverModelOverrideOptions.count)",
            surfaceColor: bottomSheetSurfaceColor,
            onInfo: {
                focusedComposerField = nil
                presentedQuickTool = .info
            },
            onFiles: {
                focusedComposerField = nil
                linkedFilePathToOpen = nil
                presentedQuickTool = .files
            },
            onDiff: {
                focusedComposerField = nil
                presentedQuickTool = .review
            },
            onWorktree: {
                focusedComposerField = nil
                presentedQuickTool = .worktree
            }
        )
    }

    var selectedModelOverrideLabel: String {
        guard applyModelOverride else { return resolvedCurrentModelLabel ?? "Default" }
        switch selectedModelOverrideOption {
        case Self.customModelOverrideOption:
            let normalized = modelOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "Custom" : normalized
        default:
            return selectedModelOverrideOption
        }
    }

    var selectedReasoningOverrideLabel: String {
        guard applyEffortOverride else { return resolvedCurrentEffortLabel ?? "Auto" }
        return selectedEffortOverride.label
    }

    var selectedFileModeLabel: String {
        if let selectedPermissionModeOverride {
            return permissionModeDisplayLabel(for: selectedPermissionModeOverride)
        }
        if let resolvedCurrentPermissionMode {
            return permissionModeDisplayLabel(for: resolvedCurrentPermissionMode)
        }
        return "Default"
    }

    var modelPickerOptions: [SessionQuickToolPickerOption] {
        var options: [SessionQuickToolPickerOption] = [
            SessionQuickToolPickerOption(
                id: Self.modelPickerDefaultOption,
                label: "Use current model"
            ),
        ]
        options.append(
            contentsOf: availableModelOverrideOptions.map { model in
                SessionQuickToolPickerOption(
                    id: Self.modelPickerPresetPrefix + model,
                    label: model
                )
            }
        )
        options.append(
            SessionQuickToolPickerOption(
                id: Self.modelPickerCustomOption,
                label: "Custom model…"
            )
        )
        return options
    }

    var effortPickerOptions: [SessionQuickToolPickerOption] {
        availableEffortSelections.map { effort in
            SessionQuickToolPickerOption(
                id: Self.effortPickerPresetPrefix + effort.rawValue,
                label: effort.label
            )
        }
    }

    var availablePermissionModeOptions: [APISessionMessagePermissionMode] {
        guard let flavor = parsedSessionFlavor else {
            return [.default, .yolo]
        }
        switch flavor {
        case .codex:
            return [.passthrough, .default, .readOnly, .safeYolo, .yolo]
        case .claude, .gemini:
            return [.default, .acceptEdits, .bypassPermissions, .plan]
        }
    }

    var permissionModePickerOptions: [SessionQuickToolPickerOption] {
        var options: [SessionQuickToolPickerOption] = [
            SessionQuickToolPickerOption(
                id: Self.permissionModePickerDefaultOption,
                label: "Use current mode"
            ),
        ]
        options.append(
            contentsOf: availablePermissionModeOptions.map { mode in
                SessionQuickToolPickerOption(
                    id: Self.permissionModePickerPresetPrefix + mode.rawValue,
                    label: permissionModeDisplayLabel(for: mode)
                )
            }
        )
        return options
    }

    var modelPickerSelection: Binding<String> {
        Binding(
            get: {
                if !applyModelOverride {
                    return Self.modelPickerDefaultOption
                }
                if selectedModelOverrideOption == Self.customModelOverrideOption {
                    return Self.modelPickerCustomOption
                }
                return Self.modelPickerPresetPrefix + selectedModelOverrideOption
            },
            set: { value in
                switch value {
                case Self.modelPickerDefaultOption:
                    applyModelOverride = false
                    selectedModelOverrideOption = ""
                    focusedComposerField = nil
                case Self.modelPickerCustomOption:
                    applyModelOverride = true
                    selectedModelOverrideOption = Self.customModelOverrideOption
                    focusedComposerField = .customModel
                default:
                    guard value.hasPrefix(Self.modelPickerPresetPrefix) else { return }
                    let model = String(value.dropFirst(Self.modelPickerPresetPrefix.count))
                    applyModelOverride = true
                    selectedModelOverrideOption = model
                    modelOverrideDraft = model
                    focusedComposerField = nil
                }
            }
        )
    }

    var effortPickerSelection: Binding<String> {
        Binding(
            get: {
                if applyEffortOverride {
                    return Self.effortPickerPresetPrefix + selectedEffortOverride.rawValue
                }
                return Self.effortPickerPresetPrefix + SessionComposerEffortSelection.auto.rawValue
            },
            set: { value in
                guard value.hasPrefix(Self.effortPickerPresetPrefix) else { return }
                let raw = String(value.dropFirst(Self.effortPickerPresetPrefix.count))
                guard let selected = SessionComposerEffortSelection(rawValue: raw) else { return }
                selectedEffortOverride = selected
                applyEffortOverride = selected != .auto
            }
        )
    }

    var permissionModePickerSelection: Binding<String> {
        Binding(
            get: {
                guard let selectedPermissionModeOverride else {
                    return Self.permissionModePickerDefaultOption
                }
                return Self.permissionModePickerPresetPrefix + selectedPermissionModeOverride.rawValue
            },
            set: { value in
                if value == Self.permissionModePickerDefaultOption {
                    selectedPermissionModeOverride = nil
                    return
                }
                guard value.hasPrefix(Self.permissionModePickerPresetPrefix) else { return }
                let raw = String(value.dropFirst(Self.permissionModePickerPresetPrefix.count))
                selectedPermissionModeOverride = APISessionMessagePermissionMode(rawValue: raw)
            }
        )
    }

    @ViewBuilder
    func quickToolDestinationView(_ tool: SessionQuickTool) -> some View {
        switch tool {
        case .info:
            SessionInfoView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
        case .files:
            SessionFileView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                initialFilePath: linkedFilePathToOpen,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("File Viewer")
            .navigationBarTitleDisplayMode(.inline)
        case .review:
            SessionReviewView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Review Diff")
            .navigationBarTitleDisplayMode(.inline)
        case .worktree:
            SessionFinishView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Finish Worktree")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func normalizedCWD(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func scrollTranscriptToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool = false
    ) {
        let snapshotCount = visibleTranscriptMessageIDs.count
        // Schedule after two runloop turns so List can reconcile backing UICollectionView.
        // This reduces invalid target index-path assertions during rapid stream updates.
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard shouldFollowTranscript else { return }
                // Skip stale requests when the transcript just shrank.
                guard visibleTranscriptMessageIDs.count >= snapshotCount else { return }

                let action = {
                    proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
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
    }

    func handleVisibleTranscriptMessageIDsChange(
        oldIDs: [String],
        newIDs: [String],
        using proxy: ScrollViewProxy
    ) {
        guard shouldFollowTranscript else { return }
        // Avoid List/UICollectionView out-of-bounds assertions during shrink updates.
        guard newIDs.count >= oldIDs.count else { return }
        scrollTranscriptToBottom(using: proxy)
    }

}
