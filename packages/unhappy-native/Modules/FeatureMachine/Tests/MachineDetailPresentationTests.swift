import Testing
import CoreKit
@testable import FeatureMachine

struct MachineDetailPresentationTests {
    @Test
    func makeBuildsDaemonAndMetadataFields() {
        let machine = APIMachine(
            id: "machine-1",
            active: true,
            activeAt: 300,
            createdAt: 100,
            updatedAt: 400,
            metadataVersion: 2,
            metadata: #"{"host":"mac-mini","online":true,"cores":8}"#,
            daemonStateVersion: 7,
            daemonState: #"{"status":"running","pid":1234}"#,
            dataEncryptionKey: nil
        )

        let presentation = MachineDetailPresentationBuilder.make(from: machine) { value in
            "ts:\(Int(value))"
        }

        #expect(presentation.machineID == "machine-1")
        #expect(presentation.activeAtText == "ts:300")
        #expect(presentation.createdAtText == "ts:100")
        #expect(presentation.updatedAtText == "ts:400")
        #expect(presentation.metadataFields.map(\.key) == ["cores", "host", "online"])
        #expect(presentation.daemonStateFields.map(\.key) == ["pid", "status"])
        #expect(presentation.daemonStateVersionText == "7")
    }

    @Test
    func makeTruncatesLongDaemonStatePreview() {
        let longPayload = String(repeating: "x", count: MachineDetailPresentationBuilder.previewLimit + 15)
        let machine = APIMachine(
            id: "machine-2",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 1,
            metadataVersion: 1,
            metadata: "{}",
            daemonStateVersion: 1,
            daemonState: longPayload,
            dataEncryptionKey: nil
        )

        let presentation = MachineDetailPresentationBuilder.make(from: machine)

        #expect(presentation.daemonStateCharacterCount == longPayload.count)
        #expect(presentation.daemonStateTruncated == true)
        #expect(presentation.daemonStatePreview?.count == MachineDetailPresentationBuilder.previewLimit)
    }
}
