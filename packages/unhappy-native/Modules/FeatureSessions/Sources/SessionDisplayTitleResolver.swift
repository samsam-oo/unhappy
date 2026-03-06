import Foundation
import CoreKit

enum SessionDisplayTitleResolver {
    static func resolvedDisplayTitle(for session: APISession) -> String? {
        resolvedDisplayTitle(for: session, context: SessionRuntimeContext(session: session))
    }

    static func resolvedDisplayTitle(
        for session: APISession,
        context: SessionRuntimeContext
    ) -> String? {
        if let normalized = normalizedDisplayName(for: session) {
            return normalized
        }

        if let summaryText = summaryText(in: [context.agentState, context.metadata]) {
            return summaryText
        }

        if let metadataName = SessionPayloadValueResolver.firstString(
            in: [context.agentState, context.metadata],
            keys: ["displayName", "name", "title", "threadName", "sessionName"]
        ) {
            let trimmed = metadataName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != session.id {
                return trimmed
            }
        }

        return nil
    }

    static func fallbackTitle(for session: APISession) -> String {
        if let seq = session.seq, seq > 0 {
            return "Session \(seq)"
        }
        return "Session"
    }

    private static func normalizedDisplayName(for session: APISession) -> String? {
        guard let raw = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != session.id else {
            return nil
        }
        return raw
    }

    private static func summaryText(in objects: [Any]) -> String? {
        for object in objects {
            if let dictionary = object as? [String: Any] {
                if let summary = dictionary["summary"] as? [String: Any],
                   let text = summary["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
                if let summary = dictionary["summary"] as? String {
                    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

}
