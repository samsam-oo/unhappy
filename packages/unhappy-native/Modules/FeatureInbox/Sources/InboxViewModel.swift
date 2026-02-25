import Foundation

@MainActor
public final class InboxViewModel: ObservableObject {
    @Published public private(set) var items: [InboxItem] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any InboxLoadingAction
    private var serverURLString: String
    private var token: String

    public init(
        loader: any InboxLoadingAction,
        serverURLString: String = "",
        token: String = ""
    ) {
        self.loader = loader
        self.serverURLString = serverURLString
        self.token = token
    }

    public func updateConfiguration(serverURLString: String, token: String) {
        self.serverURLString = serverURLString
        self.token = token
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await loader.loadInboxItems(
                serverURLString: serverURLString,
                token: token
            )
            errorMessage = nil
        } catch {
            items = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
