import Foundation
import CoreKit

public enum SessionFirstMessagePreviewResolver {
    public static func resolve(
        from messages: [APISessionMessage],
        dataEncryptionKey: String?
    ) -> String? {
        let sortedMessages = messages.sorted { lhs, rhs in
            if lhs.seq != rhs.seq {
                return lhs.seq < rhs.seq
            }
            return lhs.createdAt < rhs.createdAt
        }

        for message in sortedMessages {
            guard let content = message.content else { continue }

            let decodedPayload = SessionPayloadValueResolver.decodeJSONObject(
                payload: content.payload,
                dataEncryptionKey: dataEncryptionKey
            )
            if let text = SessionPayloadValueResolver.firstString(
                in: [decodedPayload],
                keys: ["text", "body", "content", "message", "summary", "prompt"]
            ) {
                return normalize(text)
            }

            guard content.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "encrypted" else {
                continue
            }
            if let normalizedRaw = normalize(content.payload) {
                return normalizedRaw
            }
        }

        return nil
    }

    private static func normalize(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 90 {
            return collapsed
        }
        return String(collapsed.prefix(90)) + "…"
    }
}
