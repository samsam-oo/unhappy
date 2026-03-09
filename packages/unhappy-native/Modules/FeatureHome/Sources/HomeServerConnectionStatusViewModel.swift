import Foundation

@MainActor
public final class HomeServerConnectionStatusViewModel: ObservableObject {
    @Published public private(set) var status: HomeServerConnectionStatus
    @Published public private(set) var isLoading = false

    private let loader: any HomeServerConnectionStatusLoadingAction
    private var refreshSequence = 0

    public init(
        loader: any HomeServerConnectionStatusLoadingAction,
        initialStatus: HomeServerConnectionStatus = .disconnected
    ) {
        self.loader = loader
        self.status = initialStatus
    }

    public func refresh(serverURLString: String) async {
        refreshSequence += 1
        let sequence = refreshSequence

        isLoading = true
        status = .connecting
        defer {
            if sequence == refreshSequence {
                isLoading = false
            }
        }

        let loadedStatus = await loader.loadStatus(serverURLString: serverURLString)
        guard sequence == refreshSequence else { return }

        status = loadedStatus
    }
}
