import SwiftUI
import CoreKit

struct NewSessionDirectoryBrowserSheet: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    @Binding var isPresented: Bool
    @Binding var directoryBrowserFilterText: String
    @Binding var directoryBrowserPathDraft: String
    let confirmCurrentDirectorySelection: () -> Void
    let focusedField: FocusState<FocusedField?>.Binding
    let filteredDirectoryBrowserEntries: [APIMachineDirectoryEntry]
    let directoryEntryFullPath: (APIMachineDirectoryEntry) -> String
    let loadDirectoryFromBrowserPath: (String) async -> Void
    let goToParentDirectoryFromBrowser: () async -> Void

    var body: some View {
        NavigationStack {
            browserContent
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use This Folder") {
                        confirmCurrentDirectorySelection()
                        isPresented = false
                    }
                }
            }
            .task { await loadInitialDirectory() }
        }
    }

    private var browserContent: some View {
        VStack(spacing: 0) {
            Form {
                currentPathSection
                foldersSection
            }
        }
    }

    private var currentPathSection: some View {
        Section("Current Path") {
            TextField("Go to path", text: $directoryBrowserPathDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .disabled(isDirectoryActionDisabled)
                .focused(focusedField, equals: .directoryPath)
                .onSubmit { Task { await loadFromDraftPath(confirmSelection: true) } }

            Button {
                focusedField.wrappedValue = nil
                Task { await goToParentDirectoryFromBrowser() }
            } label: {
                Label("Up One Level", systemImage: "folder")
            }
            .disabled(isDirectoryActionDisabled)
        }
    }

    private var foldersSection: some View {
        Section("Folders") {
            TextField("Filter folders", text: $directoryBrowserFilterText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .directoryFilter)

            foldersContent
        }
    }

    @ViewBuilder
    private var foldersContent: some View {
        if viewModel.isLoadingDirectory {
            HStack {
                ProgressView()
                Text("Loading folders…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = normalizedErrorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
            Button("Retry") { Task { await loadFromDraftPath(confirmSelection: false) } }
        } else if filteredDirectoryBrowserEntries.isEmpty {
            ContentUnavailableView(
                "No folders found",
                systemImage: "folder.badge.questionmark",
                description: Text("Try a different path or clear the filter.")
            )
        } else {
            ForEach(filteredDirectoryBrowserEntries) { entry in
                Button {
                    Task { await selectDirectoryEntry(entry) }
                } label: {
                    NewSessionDirectoryBrowserEntryRow(
                        name: entry.name,
                        fullPath: directoryEntryFullPath(entry)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isDirectoryActionDisabled: Bool {
        viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory
    }

    private var normalizedErrorMessage: String? {
        guard let error = viewModel.errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !error.isEmpty else {
            return nil
        }
        return error
    }

    private func loadInitialDirectory() async {
        if directoryBrowserPathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            directoryBrowserPathDraft = viewModel.directoryPath
        }
        await loadFromDraftPath(confirmSelection: false)
    }

    private func loadFromDraftPath(confirmSelection: Bool) async {
        await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
        if confirmSelection {
            confirmCurrentDirectorySelection()
        }
    }

    private func selectDirectoryEntry(_ entry: APIMachineDirectoryEntry) async {
        await viewModel.selectDirectoryEntry(
            entry,
            serverURLString: serverURLString,
            token: token
        )
        directoryBrowserPathDraft = viewModel.directoryPath
        confirmCurrentDirectorySelection()
    }
}

private struct NewSessionDirectoryBrowserEntryRow: View {
    let name: String
    let fullPath: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(fullPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
