import SwiftUI

@MainActor
struct ServerSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("API") {
                TextField("Server URL", text: $viewModel.serverURLString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("API Token", text: $viewModel.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Notes") {
                Text("This app uses direct native API calls.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
