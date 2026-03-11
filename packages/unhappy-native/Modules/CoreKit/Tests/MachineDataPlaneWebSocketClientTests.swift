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

    @Test
    func keepaliveIntervalHonorsAdvertisedIdleTimeout() {
        #expect(MachineDataPlaneNetworkTransport.keepaliveInterval(forIdleTimeoutSeconds: 45) == 22.5)
        #expect(MachineDataPlaneNetworkTransport.keepaliveInterval(forIdleTimeoutSeconds: 8) == 4)
        #expect(MachineDataPlaneNetworkTransport.keepaliveInterval(forIdleTimeoutSeconds: 1) == 1)
    }

    @Test
    func replaySafetyOnlyCoversReadLikeOperations() {
        #expect(MachineDataPlaneWebSocketClient.isOperationSafeToReplay(.machineListModels))
        #expect(MachineDataPlaneWebSocketClient.isOperationSafeToReplay(.codexListMessages))
        #expect(MachineDataPlaneWebSocketClient.isOperationSafeToReplay(.fsReadFile))
        #expect(!MachineDataPlaneWebSocketClient.isOperationSafeToReplay(.codexSendMessage))
        #expect(!MachineDataPlaneWebSocketClient.isOperationSafeToReplay(.execBash))
    }

    @Test
    func reconnectGraceIntervalPrefersLongerWindowForInteractiveOperations() {
        #expect(
            MachineDataPlaneWebSocketClient.reconnectGraceInterval(
                for: .codexSendMessage,
                baseGraceInterval: 4
            ) == 6
        )
        #expect(
            MachineDataPlaneWebSocketClient.reconnectGraceInterval(
                for: .codexListMessages,
                baseGraceInterval: 4
            ) == 4
        )
        #expect(
            MachineDataPlaneWebSocketClient.reconnectGraceInterval(
                for: .projectList,
                baseGraceInterval: 4
            ) == 4
        )
    }

    @Test
    func reconnectBackoffDelayIsBounded() {
        #expect(MachineDataPlaneWebSocketClient.reconnectBackoffDelay(attempt: 1) == 0.25)
        #expect(MachineDataPlaneWebSocketClient.reconnectBackoffDelay(attempt: 2) == 0.5)
        #expect(MachineDataPlaneWebSocketClient.reconnectBackoffDelay(attempt: 3) == 1)
        #expect(MachineDataPlaneWebSocketClient.reconnectBackoffDelay(attempt: 9) == 1.5)
    }

    @Test
    func responseTimeoutIntervalPrefersLongerWindowForInteractiveOperations() {
        #expect(
            MachineDataPlaneWebSocketClient.responseTimeoutInterval(
                for: .codexSendMessage,
                baseResponseTimeoutInterval: 12
            ) == 45
        )
        #expect(
            MachineDataPlaneWebSocketClient.responseTimeoutInterval(
                for: .codexListMessages,
                baseResponseTimeoutInterval: 12
            ) == 20
        )
        #expect(
            MachineDataPlaneWebSocketClient.responseTimeoutInterval(
                for: .projectList,
                baseResponseTimeoutInterval: 12
            ) == 20
        )
        #expect(
            MachineDataPlaneWebSocketClient.responseTimeoutInterval(
                for: .diffDifftastic,
                baseResponseTimeoutInterval: 4
            ) == 20
        )
    }

    @Test
    func dispatchCapacityUsesAdvertisedInFlightLimit() {
        #expect(MachineDataPlaneWebSocketClient.dispatchCapacity(maxInFlightStreams: nil, activeExecutions: 0) == 1)
        #expect(MachineDataPlaneWebSocketClient.dispatchCapacity(maxInFlightStreams: nil, activeExecutions: 1) == 0)
        #expect(MachineDataPlaneWebSocketClient.dispatchCapacity(maxInFlightStreams: 4, activeExecutions: 1) == 3)
        #expect(MachineDataPlaneWebSocketClient.dispatchCapacity(maxInFlightStreams: 4, activeExecutions: 4) == 0)
    }
}
