import Foundation
import CoreKit

enum DirectSessionIdentityResolver {
    static func resolve(from row: SessionLinkedUpstreamSession) -> DirectSessionIdentity? {
        guard row.summary.provider == .codex || row.summary.provider == .claude || row.summary.provider == .gemini else { return nil }
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
            provider: row.summary.provider,
            upstreamSessionID: row.summary.id,
            title: row.title,
            cwd: cwd,
            transcriptPath: nil,
            model: row.summary.model
        )
    }

    static func resolve(from session: APISession) -> DirectSessionIdentity? {
        let context = SessionRuntimeContext(session: session)
        guard let upstreamIdentity = context.upstreamIdentity else { return nil }
        guard let cwd = context.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else {
            return nil
        }

        if upstreamIdentity.provider == .codex {
            guard let transcriptPath = upstreamIdentity.transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcriptPath.isEmpty else {
                return nil
            }
            return DirectSessionIdentity(
                machineID: upstreamIdentity.machineID,
                machineDisplayName: upstreamIdentity.machineDisplayName ?? upstreamIdentity.machineID,
                provider: .codex,
                upstreamSessionID: upstreamIdentity.upstreamSessionID,
                title: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) ?? SessionDisplayTitleResolver.fallbackTitle(for: session),
                cwd: cwd,
                transcriptPath: transcriptPath,
                model: context.currentModelLabel
            )
        }

        if upstreamIdentity.provider == .claude || upstreamIdentity.provider == .gemini {
            return DirectSessionIdentity(
                machineID: upstreamIdentity.machineID,
                machineDisplayName: upstreamIdentity.machineDisplayName ?? upstreamIdentity.machineID,
                provider: upstreamIdentity.provider,
                upstreamSessionID: upstreamIdentity.upstreamSessionID,
                title: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) ?? SessionDisplayTitleResolver.fallbackTitle(for: session),
                cwd: cwd,
                transcriptPath: upstreamIdentity.transcriptPath,
                model: context.currentModelLabel
            )
        }

        return nil
    }
}
