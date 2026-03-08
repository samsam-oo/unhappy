import Foundation
import CoreKit

enum DirectSessionIdentityResolver {
    static func resolve(from row: SessionLinkedUpstreamSession) -> DirectSessionIdentity? {
        guard row.summary.provider == .codex || row.summary.provider == .claude else { return nil }
        guard let cwd = row.summary.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else {
            return nil
        }

        if row.summary.provider == .codex {
            guard let transcriptPath = row.summary.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcriptPath.isEmpty else {
                return nil
            }
            return DirectSessionIdentity(
                machineID: row.machineID,
                machineDisplayName: row.machineDisplayName,
                provider: .codex,
                upstreamSessionID: row.summary.id,
                title: row.title,
                cwd: cwd,
                transcriptPath: transcriptPath,
                model: row.summary.model
            )
        }

        return DirectSessionIdentity(
            machineID: row.machineID,
            machineDisplayName: row.machineDisplayName,
            provider: .claude,
            upstreamSessionID: row.summary.id,
            title: row.title,
            cwd: cwd,
            transcriptPath: nil,
            model: row.summary.model
        )
    }
}
