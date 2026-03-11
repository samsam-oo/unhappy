import Foundation
import Testing
import CoreKit
import SessionKit
@testable import FeatureSessions

struct SessionLoadTimeoutTests {
    @Test
    func timeoutHelperThrowsTimedOutWhenOperationStalls() async {
        await #expect(throws: MachinesAPIError.rpcTimedOut) {
            _ = try await withSessionLoadTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(1))
                return 1
            }
        }
    }
}
