import Foundation
import CoreKit

public struct AppSettingsSnapshot: Sendable, Equatable {
    public let serverURLString: String
    public let apiToken: String

    public init(serverURLString: String, apiToken: String) {
        self.serverURLString = serverURLString
        self.apiToken = apiToken
    }
}

public protocol SettingsManaging: Sendable {
    func loadSettings() async -> AppSettingsSnapshot
    func persistSettings(serverURLString: String, apiToken: String) async
}

public actor SettingsUseCase: SettingsManaging {
    private let store: any AppSettingsStore

    public init(store: any AppSettingsStore) {
        self.store = store
    }

    public func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            serverURLString: await store.serverURLString(),
            apiToken: await store.apiToken()
        )
    }

    public func persistSettings(serverURLString: String, apiToken: String) async {
        await store.setServerURLString(serverURLString)
        await store.setAPIToken(apiToken)
    }
}
