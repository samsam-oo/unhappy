import SwiftUI
import CoreKit

@MainActor
public struct SessionFileView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel

    public init(
        session: APISession,
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.session = session
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        List {
            Section("Directory") {
                TextField("Directory path", text: $viewModel.directoryPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Browse Directory") {
                    Task {
                        await viewModel.loadDirectory(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isLoadingDirectory)

                if viewModel.isLoadingDirectory {
                    ProgressView("Loading directory…")
                } else if let error = viewModel.directoryErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if !viewModel.directoryEntries.isEmpty {
                    ForEach(viewModel.directoryEntries) { entry in
                        Button {
                            Task {
                                await viewModel.selectDirectoryEntry(
                                    entry,
                                    sessionID: session.id,
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: entry.type == "directory" ? "folder" : "doc")
                                    .foregroundStyle(entry.type == "directory" ? Color.accentColor : Color.secondary)
                                Text(entry.name)
                                    .lineLimit(1)
                                Spacer()
                                if entry.type == "directory" {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Path") {
                TextField("Absolute path", text: $viewModel.filePath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Load File") {
                    Task {
                        await viewModel.loadFile(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isLoadingFile || viewModel.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Content") {
                if viewModel.isLoadingFile {
                    ProgressView("Loading file…")
                } else if let error = viewModel.fileErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if viewModel.fileContent.isEmpty {
                    Text("No content loaded")
                        .foregroundStyle(.secondary)
                } else {
                    TextEditor(text: $viewModel.fileContent)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 260)
                    Button(viewModel.isWritingFile ? "Saving…" : "Save File") {
                        Task {
                            await viewModel.writeCurrentFile(
                                sessionID: session.id,
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                    .disabled(
                        viewModel.isWritingFile ||
                        viewModel.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if let status = viewModel.writeStatusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let error = viewModel.writeErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Session File")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(serverURLString)|\(token)|\(session.id)") {
            await viewModel.loadDirectory(
                sessionID: session.id,
                serverURLString: serverURLString,
                token: token
            )
        }
    }
}
