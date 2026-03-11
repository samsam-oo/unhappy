import Foundation
import Network
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

    @Test
    func mapTransportErrorNormalizesNetworkFrameworkDisconnectedError() {
        let client = MachineDataPlaneWebSocketClient()
        let error = NWError.posix(.ENOTCONN)

        let mapped = client.mapTransportError(error)

        #expect(mapped == .rpcCallFailed("Machine data-plane socket is not connected"))
    }
}
