import Foundation
import Testing
@testable import FeatureSettings
import CoreKit

struct SettingsUseCaseTests {
    @Test
    func loadSettingsReturnsValuesFromStore() async {
        let store = MemoryAppSettingsStore(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123"
        )
        let useCase = SettingsUseCase(store: store)

        let loaded = await useCase.loadSettings()

        #expect(loaded.serverURLString == "https://api.example.com")
        #expect(loaded.apiToken == "token-123")
    }

    @Test
    func persistSettingsWritesBothValues() async {
        let store = MemoryAppSettingsStore()
        let useCase = SettingsUseCase(store: store)

        await useCase.persistSettings(
            serverURLString: "https://new.example.com",
            apiToken: "next-token"
        )

        #expect(await store.serverURLString() == "https://new.example.com")
        #expect(await store.apiToken() == "next-token")
    }
}

private actor MemoryAppSettingsStore: AppSettingsStore {
    private var savedServerURLString: String
    private var savedAPIToken: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = ""
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
    }

    func serverURLString() async -> String { savedServerURLString }
    func apiToken() async -> String { savedAPIToken }
    func setServerURLString(_ value: String) async { savedServerURLString = value }
    func setAPIToken(_ value: String) async { savedAPIToken = value }
}
