import Foundation
import CoreKit

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var serverURLString: String {
        didSet {
            store.setServerURLString(serverURLString)
        }
    }

    @Published public var apiToken: String {
        didSet {
            store.setAPIToken(apiToken)
        }
    }

    private let store: any AppSettingsStore

    public init(store: any AppSettingsStore) {
        self.store = store
        self.serverURLString = store.serverURLString()
        self.apiToken = store.apiToken()
    }
}
