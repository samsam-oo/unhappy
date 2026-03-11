import Testing
import CoreKit
import SessionKit
@testable import FeatureNewSession

struct NewSessionMachinePresentationTests {
    @Test
    func usesDisplayNameWhenAvailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"displayName":"MacBook Pro","host":"mbp.local"}"#
        )

        let label = NewSessionMachinePresentation.displayName(for: machine)

        #expect(label == "MacBook Pro")
    }

    @Test
    func fallsBackToHostWhenDisplayNameMissing() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"host":"studio-mac"}"#
        )

        let label = NewSessionMachinePresentation.displayName(for: machine)

        #expect(label == "studio-mac")
    }

    @Test
    func fallsBackToMachineIDWhenMetadataUnavailable() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: "not-json"
        )

        let label = NewSessionMachinePresentation.displayName(for: machine)

        #expect(label == "machine-1")
    }

    @Test
    func prefersNonGenericHostWhenGenericAndSpecificHostsBothExist() {
        let machine = makeMachine(
            id: "machine-1",
            metadata: #"{"host":"mac","details":{"hostname":"studio-mac.local"}}"#
        )

        let label = NewSessionMachinePresentation.displayName(for: machine)

        #expect(label == "studio-mac")
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
