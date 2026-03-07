import SwiftUI
import CoreKit

struct SessionQuickToolPickerOption: Identifiable, Equatable {
    let id: String
    let label: String
}

struct SessionQuickToolsDockBar: View {
    private enum PresentedPicker: String, Identifiable {
        case model
        case effort
        case permissionMode

        var id: String { rawValue }
    }

    let supportsReasoningEffortOverride: Bool
    let selectedModelOverrideLabel: String
    let selectedReasoningOverrideLabel: String
    let selectedFileModeLabel: String
    let modelPickerOptions: [SessionQuickToolPickerOption]
    let effortPickerOptions: [SessionQuickToolPickerOption]
    let permissionModePickerOptions: [SessionQuickToolPickerOption]
    let modelPickerSelection: Binding<String>
    let effortPickerSelection: Binding<String>
    let permissionModePickerSelection: Binding<String>
    let sessionIdentity: String
    let surfaceColor: Color
    let onInfo: () -> Void
    let onFiles: () -> Void
    let onDiff: () -> Void
    let onWorktree: () -> Void

    private let quickToolsFadeWidth: CGFloat = 16
    private let quickToolsBarHeight: CGFloat = 36
    @State private var presentedPicker: PresentedPicker?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                modelMenuButton

                if supportsReasoningEffortOverride {
                    effortMenuButton
                }

                fileModeMenuButton

                dockChipButton(
                    title: "Info",
                    systemImage: "info.circle",
                    action: onInfo
                )
                dockChipButton(
                    title: "Files",
                    systemImage: "doc.text",
                    action: onFiles
                )
                dockChipButton(
                    title: "Diff",
                    systemImage: "doc.text.magnifyingglass",
                    action: onDiff
                )
                dockChipButton(
                    title: "Worktree",
                    systemImage: "checkmark.circle",
                    action: onWorktree
                )
            }
            .padding(.horizontal, quickToolsFadeWidth)
            .padding(.vertical, 4)
        }
        .defaultScrollAnchor(.leading)
        .id(sessionIdentity)
        .frame(height: quickToolsBarHeight)
        .sheet(item: $presentedPicker) { picker in
            pickerSheet(for: picker)
        }
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [surfaceColor, surfaceColor.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: quickToolsFadeWidth)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [surfaceColor.opacity(0), surfaceColor],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: quickToolsFadeWidth)
            .allowsHitTesting(false)
        }
    }

    private var modelMenuButton: some View {
        dockChipButton(
            title: selectedModelOverrideLabel,
            systemImage: "cpu"
        ) {
            presentedPicker = .model
        }
    }

    private var effortMenuButton: some View {
        dockChipButton(
            title: selectedReasoningOverrideLabel,
            systemImage: "brain.head.profile"
        ) {
            presentedPicker = .effort
        }
    }

    private var fileModeMenuButton: some View {
        dockChipButton(
            title: selectedFileModeLabel,
            systemImage: "doc.badge.gearshape"
        ) {
            presentedPicker = .permissionMode
        }
    }

    private func dockChipButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .modifier(DockChipModifier(tone: .neutral))
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    @ViewBuilder
    private func pickerSheet(for picker: PresentedPicker) -> some View {
        switch picker {
        case .model:
            SessionQuickToolSelectionSheet(
                title: "Model",
                selectedOptionID: modelPickerSelection.wrappedValue,
                options: modelPickerOptions
            ) { optionID in
                modelPickerSelection.wrappedValue = optionID
                presentedPicker = nil
            }
        case .effort:
            SessionQuickToolSelectionSheet(
                title: "Reasoning Effort",
                selectedOptionID: effortPickerSelection.wrappedValue,
                options: effortPickerOptions
            ) { optionID in
                effortPickerSelection.wrappedValue = optionID
                presentedPicker = nil
            }
        case .permissionMode:
            SessionQuickToolSelectionSheet(
                title: "File Mode",
                selectedOptionID: permissionModePickerSelection.wrappedValue,
                options: permissionModePickerOptions
            ) { optionID in
                permissionModePickerSelection.wrappedValue = optionID
                presentedPicker = nil
            }
        }
    }
}

private struct SessionQuickToolSelectionSheet: View {
    let title: String
    let selectedOptionID: String
    let options: [SessionQuickToolPickerOption]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    onSelect(option.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if option.id == selectedOptionID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SessionRenameSheet: View {
    @Binding var isPresented: Bool
    @Binding var renameDraft: String
    let isRenaming: Bool
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Session Title") {
                    TextField("Session title", text: $renameDraft)
                        .textInputAutocapitalization(.never)
                    Text("Leave empty to clear the custom title.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        isPresented = false
                        onSave(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(isRenaming)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SessionToolbarTrailingMenu: View {
    let isBusy: Bool
    let onRename: () -> Void
    let onArchive: () -> Void
    @State private var isShowingActions = false

    var body: some View {
        if isBusy {
            ProgressView()
        } else {
            Button {
                isShowingActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressableScaleButtonStyle())
            .confirmationDialog(
                "Session Actions",
                isPresented: $isShowingActions,
                titleVisibility: .visible
            ) {
                Button("Rename", action: onRename)
                Button("Archive", role: .destructive, action: onArchive)
            }
        }
    }
}
