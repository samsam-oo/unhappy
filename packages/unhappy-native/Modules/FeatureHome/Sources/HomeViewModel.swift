import Foundation
import CoreKit

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var serverURLString: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            scheduleServerURLPersistence(value: serverURLString)
        }
    }

    @Published public var apiToken: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            scheduleAPITokenPersistence(value: apiToken)
        }
    }

    private let store: any AppSettingsStore
    private var hasLoadedInitialSettings = false
    private var serverURLPersistenceTask: Task<Void, Never>?
    private var apiTokenPersistenceTask: Task<Void, Never>?

    public init(store: any AppSettingsStore) {
        self.store = store
        self.serverURLString = "https://api.unhappy.im"
        self.apiToken = ""
    }

    deinit {
        serverURLPersistenceTask?.cancel()
        apiTokenPersistenceTask?.cancel()
    }

    public func loadFromStore() async {
        hasLoadedInitialSettings = false
        let loadedServerURLString = await store.serverURLString()
        let loadedAPIToken = await store.apiToken()
        serverURLString = loadedServerURLString
        apiToken = loadedAPIToken
        hasLoadedInitialSettings = true
    }

    func waitForPendingPersistence() async {
        await serverURLPersistenceTask?.value
        await apiTokenPersistenceTask?.value
    }

    private func scheduleServerURLPersistence(value: String) {
        let store = self.store
        serverURLPersistenceTask?.cancel()
        serverURLPersistenceTask = Task {
            guard !Task.isCancelled else { return }
            await store.setServerURLString(value)
        }
    }

    private func scheduleAPITokenPersistence(value: String) {
        let store = self.store
        apiTokenPersistenceTask?.cancel()
        apiTokenPersistenceTask = Task {
            guard !Task.isCancelled else { return }
            await store.setAPIToken(value)
        }
    }
}
