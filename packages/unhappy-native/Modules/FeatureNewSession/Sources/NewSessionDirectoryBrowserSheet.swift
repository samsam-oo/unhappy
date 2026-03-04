import SwiftUI
import CoreKit

struct NewSessionDirectoryBrowserSheet: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    @Binding var isPresented: Bool
    @Binding var directoryBrowserFilterText: String
    @Binding var directoryBrowserPathDraft: String
    let focusedField: FocusState<FocusedField?>.Binding
    let filteredDirectoryBrowserEntries: [APIMachineDirectoryEntry]
    let directoryEntryFullPath: (APIMachineDirectoryEntry) -> String
    let loadDirectoryFromBrowserPath: (String) async -> Void
    let goToParentDirectoryFromBrowser: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Current Path") {
                        TextField("Go to path", text: $directoryBrowserPathDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .disabled(
                                viewModel.selectedMachineID == nil ||
                                viewModel.isLoadingDirectory
                            )
                            .focused(focusedField, equals: .directoryPath)
                            .onSubmit {
                                Task {
                                    await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
                                }
                            }

                        Button {
                            Task {
                                await goToParentDirectoryFromBrowser()
                            }
                        } label: {
                            Label("Up One Level", systemImage: "folder")
                        }
                        .disabled(viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory)
                    }

                    Section("Folders") {
                        TextField("Filter folders", text: $directoryBrowserFilterText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused(focusedField, equals: .directoryFilter)

                        if viewModel.isLoadingDirectory {
                            HStack {
                                ProgressView()
                                Text("Loading folders…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = viewModel.errorMessage,
                                  !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                            Button("Retry") {
                                Task {
                                    await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
                                }
                            }
                        } else if filteredDirectoryBrowserEntries.isEmpty {
                            ContentUnavailableView(
                                "No folders found",
                                systemImage: "folder.badge.questionmark",
                                description: Text("Try a different path or clear the filter.")
                            )
                        } else {
                            ForEach(filteredDirectoryBrowserEntries) { entry in
                                Button {
                                    Task {
                                        await viewModel.selectDirectoryEntry(
                                            entry,
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                        directoryBrowserPathDraft = viewModel.directoryPath
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder")
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .lineLimit(1)
                                            Text(directoryEntryFullPath(entry))
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField.wrappedValue = nil
                }
            )
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use This Folder") { isPresented = false }
                }
            }
            .task {
                if directoryBrowserPathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    directoryBrowserPathDraft = viewModel.directoryPath
                }
                await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
            }
        }
    }
}
