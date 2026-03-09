import Testing
import CoreKit
import SecurityKit
@testable import FeatureMachine

struct MachineDisplayNameResolverTests {
    @Test
    func prefersNonGenericNestedHostOverGenericRootHost() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"host":"mac","machine":{"hostname":"dstadminui-MacBookPro.local"}}"#
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "dstadminui-MacBookPro")
    }

    @Test
    func fallsBackToFallbackLabelWhenOnlyGenericHostAvailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"host":"mac"}"#
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "Machine")
    }

    @Test
    func fallsBackToFallbackLabelWhenMetadataUnavailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: "not-json"
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "Machine")
    }

    @Test
    func decryptsMetadataWithLocalMachineKeyFallback() throws {
        let unhappyHomeURL = try makeTemporaryUnhappyHome(
            machineID: "machine-1",
            machineKey: Data(repeating: 0x11, count: 32)
        )
        let encryptedMetadata = try MachineDataPlaneEncryption.encryptJSONPayload(
            ["host": "skyline-mac.local"],
            dataKey: Data(repeating: 0x11, count: 32)
        )

        setenv("UNHAPPY_HOME_DIR", unhappyHomeURL.path, 1)
        defer { unsetenv("UNHAPPY_HOME_DIR") }

        let machine = makeMachine(
            id: "machine-1",
            metadata: encryptedMetadata
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "skyline-mac")
    }

    private func makeMachine(id: String, metadata: String) -> APIMachine {
        APIMachine(
            id: id,
            active: true,
            activeAt: 0,
            createdAt: 0,
            updatedAt: 0,
            metadataVersion: 1,
            metadata: metadata,
            daemonStateVersion: 0,
            daemonState: nil,
            dataEncryptionKey: nil
        )
    }

    private func makeTemporaryUnhappyHome(
        machineID: String,
        machineKey: Data
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let accessKeyURL = root.appendingPathComponent("access.key")
        let settingsURL = root.appendingPathComponent("settings.json")

        let accessKeyObject: [String: Any] = [
            "encryption": [
                "machineKey": machineKey.base64EncodedString(),
            ],
            "token": "token",
        ]
        let settingsObject: [String: Any] = [
            "machineId": machineID,
        ]

        try JSONSerialization.data(withJSONObject: accessKeyObject, options: [.sortedKeys])
            .write(to: accessKeyURL)
        try JSONSerialization.data(withJSONObject: settingsObject, options: [.sortedKeys])
            .write(to: settingsURL)

        return root
    }
}
