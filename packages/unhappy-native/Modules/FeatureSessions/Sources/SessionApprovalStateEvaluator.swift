import Foundation

enum SessionApprovalStateEvaluator {
    static func hasPendingApprovalRequest(
        agentState: [String: Any],
        metadata: [String: Any]
    ) -> Bool {
        let sources = [agentState, metadata]

        if let explicit = SessionPayloadValueResolver.firstBool(
            in: sources,
            keys: [
                "requiresUserApproval",
                "needsApproval",
                "approvalRequired",
                "approvalPending",
                "permissionPending",
                "waitingApproval",
                "awaitingApproval",
            ]
        ) {
            return explicit
        }

        if SessionPayloadValueResolver.hasNonEmptyArray(
            in: sources,
            keys: [
                "pendingPermissions",
                "approvalRequests",
                "permissionRequests",
                "pendingApprovalRequests",
            ]
        ) {
            return true
        }

        if SessionPayloadValueResolver.hasNonEmptyDictionary(
            in: sources,
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap",
            ]
        ) {
            return true
        }

        if let status = SessionPayloadValueResolver.firstString(
            in: sources,
            keys: ["status", "state", "phase"]
        )?.lowercased(),
           status.contains("approval") || status.contains("permission") {
            return true
        }

        return false
    }
}
