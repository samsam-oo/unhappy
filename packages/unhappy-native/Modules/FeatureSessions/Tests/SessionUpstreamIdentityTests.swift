import Testing
@testable import FeatureSessions
import CoreKit

struct SessionUpstreamIdentityTests {
    @Test
    func parsesUpstreamIdentityFromSessionMetadata() {
        let session = APISession(
            id: "session-1",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 2,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","cwd":"/tmp/project","displayName":"Work Mac"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let identity = SessionUpstreamIdentity(session: session)

        #expect(identity?.machineID == "machine-1")
        #expect(identity?.provider == .codex)
        #expect(identity?.upstreamSessionID == "thread-1")
        #expect(identity?.workingDirectory == "/tmp/project")
        #expect(identity?.machineDisplayName == "Work Mac")
        #expect(identity?.key == "machine-1|codex|thread-1")
    }

    @Test
    func parsesProviderAndSessionIDFromAgentStateFallback() {
        let session = APISession(
            id: "session-2",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 2,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-2"}"#,
            agentState: #"{"provider":"claude","upstreamSessionId":"claude-session-1","directory":"/tmp/claude"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let identity = SessionUpstreamIdentity(session: session)

        #expect(identity?.machineID == "machine-2")
        #expect(identity?.provider == .claude)
        #expect(identity?.upstreamSessionID == "claude-session-1")
        #expect(identity?.workingDirectory == "/tmp/claude")
    }

    @Test
    func rejectsOpaqueMachineDisplayNames() {
        let session = APISession(
            id: "session-3",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 2,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-3","flavor":"codex","agentSessionId":"thread-3","displayName":"4d8e2a5d0df842d3a8bcd89f7e1a12cf"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let identity = SessionUpstreamIdentity(session: session)

        #expect(identity?.machineDisplayName == nil)
    }
}
