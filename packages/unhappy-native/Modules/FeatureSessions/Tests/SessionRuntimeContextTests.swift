import Testing
@testable import FeatureSessions
import CoreKit

struct SessionRuntimeContextTests {
    @Test
    func resolvesProviderAndOverridesFromSessionPayloads() {
        let session = APISession(
            id: "session-1",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","permissionMode":"passthrough"}"#,
            agentState: #"{"currentModel":"gpt-5.4","reasoningEffort":"xhigh","collab":{"activeCount":2},"requests":{"req-1":{"toolName":"bash"}}}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let context = SessionRuntimeContext(session: session)

        #expect(context.provider == .codex)
        #expect(context.sessionAgent == .codex)
        #expect(context.currentModelLabel == "gpt-5.4")
        #expect(context.currentEffortLabel == "xhigh")
        #expect(context.currentPermissionMode == .passthrough)
        #expect(context.collabInProgressCount == 2)
        #expect(context.requiresApproval == true)
        #expect(context.upstreamIdentity?.key == "machine-1|codex|thread-1")
    }

    @Test
    func fallsBackToAgentStateProviderWhenNoUpstreamIdentityExists() {
        let session = APISession(
            id: "session-2",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 2,
            metadataVersion: 1,
            metadata: #"{"displayName":"Standalone"}"#,
            agentState: #"{"provider":"claude","directory":"/tmp/project"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let context = SessionRuntimeContext(session: session)

        #expect(context.provider == .claude)
        #expect(context.sessionAgent == .claude)
        #expect(context.upstreamIdentity == nil)
        #expect(context.workingDirectory == "/tmp/project")
    }
}
