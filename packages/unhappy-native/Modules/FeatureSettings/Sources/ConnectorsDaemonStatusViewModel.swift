import Foundation

@MainActor
public final class ConnectorsDaemonStatusViewModel: ObservableObject {
    @Published public private(set) var snapshot: DaemonStatusSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any DaemonStatusLoadingAction

    public init(loader: any DaemonStatusLoadingAction) {
        self.loader = loader
    }

    public func load(serverURLString: String, token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await loader.loadStatus(serverURLString: serverURLString, token: token)
        } catch {
            snapshot = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
