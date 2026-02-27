import Testing
import CoreKit
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
    func fallsBackToGenericHostWhenOnlyHostAvailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"host":"mac"}"#
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "mac")
    }

    @Test
    func fallsBackToMachineIDWhenMetadataUnavailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: "not-json"
        )

        let label = MachineDisplayNameResolver.displayName(for: machine)

        #expect(label == "machine-1")
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
}
