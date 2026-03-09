import Foundation
import Testing
import SecurityKit

struct MachineDataPlaneEncryptionTests {
    @Test
    func resolveMachineDataKeyFallsBackToLocalAccessKeyForMatchingMachine() throws {
        let unhappyHomeURL = try makeTemporaryUnhappyHome(
            machineID: "machine-1",
            machineKey: Data(repeating: 0xAB, count: 32)
        )

        setenv("UNHAPPY_HOME_DIR", unhappyHomeURL.path, 1)
        defer { unsetenv("UNHAPPY_HOME_DIR") }

        let resolved = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: nil,
            machineID: "machine-1"
        )

        #expect(resolved == Data(repeating: 0xAB, count: 32))
    }

    @Test
    func resolveMachineDataKeyDoesNotUseLocalAccessKeyForDifferentMachine() throws {
        let unhappyHomeURL = try makeTemporaryUnhappyHome(
            machineID: "machine-1",
            machineKey: Data(repeating: 0xCD, count: 32)
        )

        setenv("UNHAPPY_HOME_DIR", unhappyHomeURL.path, 1)
        defer { unsetenv("UNHAPPY_HOME_DIR") }

        let resolved = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: nil,
            machineID: "machine-2"
        )

        #expect(resolved == nil)
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
