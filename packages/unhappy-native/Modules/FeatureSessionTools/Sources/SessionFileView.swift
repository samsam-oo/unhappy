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
                    ScrollView(.vertical) {
                        Text(viewModel.fileContent)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Session File")
        .navigationBarTitleDisplayMode(.inline)
    }
}
