import Foundation
import Testing
@testable import CoreKit

struct MachineDataPlaneWebSocketClientTests {
    @Test
    func mapTransportErrorNormalizesSocketDisconnectedPOSIXError() {
        let client = MachineDataPlaneWebSocketClient()
        let error = NSError(domain: NSPOSIXErrorDomain, code: 57)

        let mapped = client.mapTransportError(error)

        #expect(mapped == .rpcCallFailed("Machine data-plane socket is not connected"))
    }
}
