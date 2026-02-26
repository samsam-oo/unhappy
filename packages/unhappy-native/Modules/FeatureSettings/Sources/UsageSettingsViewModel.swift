import Foundation

@MainActor
public final class UsageSettingsViewModel: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public private(set) var snapshot: SettingsUsageSnapshot?
    @Published public private(set) var errorMessage: String?

    private let usageLoader: any SettingsUsageLoadingAction

    public init(usageLoader: any SettingsUsageLoadingAction) {
        self.usageLoader = usageLoader
    }

    public func loadUsage(serverURLString: String, token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await usageLoader.loadUsage(
                serverURLString: serverURLString,
                token: token
            )
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
