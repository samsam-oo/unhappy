import Foundation

@MainActor
public final class InboxViewModel: ObservableObject {
    @Published public private(set) var items: [InboxItem] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any InboxLoadingAction

    public init(loader: any InboxLoadingAction) {
        self.loader = loader
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await loader.loadInboxItems()
            errorMessage = nil
        } catch {
            items = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
