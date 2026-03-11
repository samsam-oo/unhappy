import Foundation
import CoreKit
import SessionKit

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
                wrappedMachineDataEncryptionKey: row.wrappedMachineDataEncryptionKey,
                provider: .codex,
                upstreamSessionID: row.summary.id,
                title: row.title,
                cwd: cwd,
                transcriptPath: transcriptPath,
                model: row.summary.model,
                effort: row.summary.effort.map { NewSessionReasoningEffort(threadEffort: $0) },
                permissionMode: nil,
                collabInProgressCount: 0
            )
        }

        return DirectSessionIdentity(
            machineID: row.machineID,
            machineDisplayName: row.machineDisplayName,
            wrappedMachineDataEncryptionKey: row.wrappedMachineDataEncryptionKey,
            provider: row.summary.provider,
            upstreamSessionID: row.summary.id,
            title: row.title,
            cwd: cwd,
            transcriptPath: nil,
            model: row.summary.model,
            effort: row.summary.effort.map { NewSessionReasoningEffort(threadEffort: $0) },
            permissionMode: nil,
            collabInProgressCount: 0
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
                wrappedMachineDataEncryptionKey: session.dataEncryptionKey,
                provider: .codex,
                upstreamSessionID: upstreamIdentity.upstreamSessionID,
                title: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) ?? SessionDisplayTitleResolver.fallbackTitle(for: session),
                cwd: cwd,
                transcriptPath: transcriptPath,
                model: context.currentModelLabel,
                effort: context.currentEffortLabel.flatMap { NewSessionReasoningEffort.fromBackend($0) },
                permissionMode: context.currentPermissionMode,
                collabInProgressCount: context.collabInProgressCount
            )
        }

        if upstreamIdentity.provider == .claude || upstreamIdentity.provider == .gemini {
            return DirectSessionIdentity(
                machineID: upstreamIdentity.machineID,
                machineDisplayName: upstreamIdentity.machineDisplayName ?? upstreamIdentity.machineID,
                wrappedMachineDataEncryptionKey: session.dataEncryptionKey,
                provider: upstreamIdentity.provider,
                upstreamSessionID: upstreamIdentity.upstreamSessionID,
                title: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) ?? SessionDisplayTitleResolver.fallbackTitle(for: session),
                cwd: cwd,
                transcriptPath: upstreamIdentity.transcriptPath,
                model: context.currentModelLabel,
                effort: context.currentEffortLabel.flatMap { NewSessionReasoningEffort.fromBackend($0) },
                permissionMode: context.currentPermissionMode,
                collabInProgressCount: context.collabInProgressCount
            )
        }

        return nil
    }
}
