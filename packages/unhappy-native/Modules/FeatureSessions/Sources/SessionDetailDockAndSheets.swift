import SwiftUI
import CoreKit

struct SessionQuickToolPickerOption: Identifiable, Equatable {
    let id: String
    let label: String
}

struct SessionQuickToolsDockBar: View {
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
        Menu {
            ForEach(modelPickerOptions) { option in
                Button {
                    modelPickerSelection.wrappedValue = option.id
                } label: {
                    if modelPickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedModelOverrideLabel, systemImage: "cpu")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var effortMenuButton: some View {
        Menu {
            ForEach(effortPickerOptions) { option in
                Button {
                    effortPickerSelection.wrappedValue = option.id
                } label: {
                    if effortPickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedReasoningOverrideLabel, systemImage: "brain.head.profile")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var fileModeMenuButton: some View {
        Menu {
            ForEach(permissionModePickerOptions) { option in
                Button {
                    permissionModePickerSelection.wrappedValue = option.id
                } label: {
                    if permissionModePickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedFileModeLabel, systemImage: "doc.badge.gearshape")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
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

    var body: some View {
        if isBusy {
            ProgressView()
        } else {
            Menu {
                Button("Rename", systemImage: "pencil", action: onRename)
                Button("Archive", systemImage: "archivebox", role: .destructive, action: onArchive)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
    }
}
