import SwiftUI

public struct SettingsView: View {
    @Binding private var serverURLString: String
    @Binding private var apiToken: String

    public init(serverURLString: Binding<String>, apiToken: Binding<String>) {
        _serverURLString = serverURLString
        _apiToken = apiToken
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Server URL", text: $serverURLString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    Text("This app uses direct native API calls.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(serverURLString: .constant("https://api.unhappy.im"), apiToken: .constant(""))
}
