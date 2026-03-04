import SwiftUI
import CoreKit

@MainActor
public struct SessionFileView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel
    @State private var contentMode: SessionFileContentMode = .file

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
            directorySection
            pathSection
            contentSection
        }
        .navigationTitle("Session File")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(serverURLString)|\(token)|\(session.id)") {
            await loadDirectory()
        }
    }

    private var directorySection: some View {
        Section("Directory") {
            TextField("Directory path", text: $viewModel.directoryPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Browse Directory") {
                Task { await loadDirectory() }
            }
            .disabled(viewModel.isLoadingDirectory)

            directoryEntriesContent
        }
    }

    @ViewBuilder
    private var directoryEntriesContent: some View {
        if viewModel.isLoadingDirectory {
            ProgressView("Loading directory…")
        } else if let error = viewModel.directoryErrorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if !viewModel.directoryEntries.isEmpty {
            ForEach(viewModel.directoryEntries) { entry in
                Button {
                    Task { await selectDirectoryEntry(entry) }
                } label: {
                    SessionDirectoryEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pathSection: some View {
        Section("Path") {
            TextField("Absolute path", text: $viewModel.filePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button("Load File") {
                    Task { await loadFile() }
                }
                .disabled(
                    viewModel.isLoadingFile ||
                    viewModel.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Load Diff") {
                    Task { await loadDiff() }
                }
                .disabled(
                    viewModel.isLoadingFileDiff ||
                    viewModel.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var contentSection: some View {
        Section("Content") {
            Picker("View", selection: $contentMode) {
                Text("File").tag(SessionFileContentMode.file)
                Text("Diff").tag(SessionFileContentMode.diff)
            }
            .pickerStyle(.segmented)

            switch contentMode {
            case .file:
                fileContentSection
            case .diff:
                diffContentSection
            }
        }
    }

    @ViewBuilder
    private var fileContentSection: some View {
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
                Task { await saveFile() }
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

    @ViewBuilder
    private var diffContentSection: some View {
        if viewModel.isLoadingFileDiff {
            ProgressView("Loading diff…")
        } else if let error = viewModel.fileDiffErrorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if viewModel.fileDiffOutput.isEmpty && viewModel.fileDiffStderr.isEmpty {
            Text("No diff output loaded")
                .foregroundStyle(.secondary)
        } else {
            if let exitCode = viewModel.fileDiffExitCode {
                Text("Exit code: \(exitCode)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(exitCode == 0 ? .green : .secondary)
            }
            if !viewModel.fileDiffOutput.isEmpty {
                ScrollView(.vertical) {
                    Text(viewModel.fileDiffOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .frame(minHeight: 260)
            }
            if !viewModel.fileDiffStderr.isEmpty {
                Text(viewModel.fileDiffStderr)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func loadDirectory() async {
        await viewModel.loadDirectory(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
    }

    private func selectDirectoryEntry(_ entry: APISessionDirectoryEntry) async {
        await viewModel.selectDirectoryEntry(
            entry,
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
    }

    private func loadFile() async {
        await viewModel.loadFile(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
        contentMode = .file
    }

    private func loadDiff() async {
        await viewModel.loadFileDiff(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
        contentMode = .diff
    }

    private func saveFile() async {
        await viewModel.writeCurrentFile(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
    }
}

private enum SessionFileContentMode: String, CaseIterable {
    case file
    case diff
}

private struct SessionDirectoryEntryRow: View {
    let entry: APISessionDirectoryEntry

    var body: some View {
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
}
