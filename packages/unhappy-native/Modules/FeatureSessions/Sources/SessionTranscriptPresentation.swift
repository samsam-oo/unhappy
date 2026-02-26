import Foundation
import CryptoKit
import CoreKit

enum SessionTranscriptEntryRole: String, Equatable, Sendable {
    case user
    case agent
    case system

    var badgeTitle: String {
        switch self {
        case .user:
            return "You"
        case .agent:
            return "Agent"
        case .system:
            return "System"
        }
    }
}

enum SessionTranscriptEntryKind: String, Equatable, Sendable {
    case text
    case thinking
    case toolCall
    case toolResult
    case event
    case raw
}

struct SessionTranscriptEntry: Identifiable, Equatable, Sendable {
    let id: String
    let role: SessionTranscriptEntryRole
    let kind: SessionTranscriptEntryKind
    let title: String?
    let body: String
}

struct SessionTranscriptMessagePresentation: Equatable, Sendable {
    let messageID: String
    let sequenceText: String
    let createdAtText: String
    let entries: [SessionTranscriptEntry]
}

enum SessionTranscriptPresentationBuilder {
    private static let entryBodyLimit = 8_000

    static func make(
        from message: APISessionMessage,
        dataEncryptionKey: String?,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> SessionTranscriptMessagePresentation {
        let payloadString = decodePayloadString(
            content: message.content,
            dataEncryptionKey: dataEncryptionKey
        )

        let entries = parseEntries(
            payloadString: payloadString,
            messageID: message.id
        )

        return SessionTranscriptMessagePresentation(
            messageID: message.id,
            sequenceText: "#\(message.seq)",
            createdAtText: timestampFormatter(message.createdAt),
            entries: entries
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private static func parseEntries(
        payloadString: String?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let payloadString, !payloadString.isEmpty else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Empty payload",
                    body: "No message content"
                )
            ]
        }

        guard let jsonData = payloadString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Raw payload",
                    body: payloadString
                )
            ]
        }

        guard let dictionary = object as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Raw payload",
                    body: stringify(object)
                )
            ]
        }

        let role = (dictionary["role"] as? String)?.lowercased()
        switch role {
        case "user":
            return parseUserRecord(dictionary, messageID: messageID)
        case "agent":
            return parseAgentRecord(dictionary, messageID: messageID)
        default:
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Unknown role",
                    body: stringify(dictionary)
                )
            ]
        }
    }

    private static func parseUserRecord(
        _ record: [String: Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let content = record["content"] as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: stringify(record["content"])
                )
            ]
        }

        if let type = content["type"] as? String, type == "text" {
            let text = normalizedText(content["text"]) ?? stringify(content)
            return [
                makeEntry(
                    id: "\(messageID)-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: text
                )
            ]
        }

        return [
            makeEntry(
                id: "\(messageID)-user",
                role: .user,
                kind: .raw,
                title: "User payload",
                body: stringify(content)
            )
        ]
    }

    private static func parseAgentRecord(
        _ record: [String: Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let content = record["content"] as? [String: Any],
              let contentType = content["type"] as? String else {
            return [
                makeEntry(
                    id: "\(messageID)-agent",
                    role: .agent,
                    kind: .raw,
                    title: "Agent payload",
                    body: stringify(record["content"])
                )
            ]
        }

        switch contentType {
        case "output":
            return parseOutputEnvelope(
                content["data"],
                messageID: messageID
            )
        case "event":
            return parseEventEnvelope(
                content["data"],
                messageID: messageID
            )
        case "codex", "acp":
            return parseACPEnvelope(
                content["data"],
                messageID: messageID
            )
        default:
            return [
                makeEntry(
                    id: "\(messageID)-agent",
                    role: .agent,
                    kind: .raw,
                    title: "Agent \(contentType)",
                    body: stringify(content)
                )
            ]
        }
    }

    private static func parseOutputEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let dictionary = data as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-output",
                    role: .agent,
                    kind: .raw,
                    title: "Output",
                    body: stringify(data)
                )
            ]
        }

        guard let type = dictionary["type"] as? String else {
            return [
                makeEntry(
                    id: "\(messageID)-output",
                    role: .agent,
                    kind: .raw,
                    title: "Output",
                    body: stringify(dictionary)
                )
            ]
        }

        switch type {
        case "assistant":
            return parseAssistantMessage(dictionary["message"], messageID: messageID)
        case "user":
            return parseOutputUserMessage(dictionary["message"], messageID: messageID)
        case "summary":
            let summary = normalizedText(dictionary["summary"]) ?? stringify(dictionary["summary"])
            return [
                makeEntry(
                    id: "\(messageID)-summary",
                    role: .agent,
                    kind: .event,
                    title: "Summary",
                    body: summary
                )
            ]
        case "result", "system":
            return [
                makeEntry(
                    id: "\(messageID)-\(type)",
                    role: .system,
                    kind: .event,
                    title: type.capitalized,
                    body: stringify(dictionary)
                )
            ]
        default:
            return [
                makeEntry(
                    id: "\(messageID)-output-\(type)",
                    role: .agent,
                    kind: .raw,
                    title: "Output \(type)",
                    body: stringify(dictionary)
                )
            ]
        }
    }

    private static func parseAssistantMessage(
        _ messageValue: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let message = messageValue as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-assistant",
                    role: .agent,
                    kind: .raw,
                    title: "Assistant",
                    body: stringify(messageValue)
                )
            ]
        }

        guard let contentArray = message["content"] as? [Any], !contentArray.isEmpty else {
            return [
                makeEntry(
                    id: "\(messageID)-assistant",
                    role: .agent,
                    kind: .raw,
                    title: "Assistant",
                    body: stringify(message)
                )
            ]
        }

        var entries: [SessionTranscriptEntry] = []
        for (index, item) in contentArray.enumerated() {
            guard let chunk = item as? [String: Any],
                  let type = chunk["type"] as? String else {
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .raw,
                        title: "Chunk",
                        body: stringify(item)
                    )
                )
                continue
            }

            switch type {
            case "text":
                let text = normalizedText(chunk["text"]) ?? stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                )
            case "thinking":
                let text = normalizedText(chunk["thinking"]) ?? normalizedText(chunk["text"]) ?? stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .thinking,
                        title: "Thinking",
                        body: text
                    )
                )
            case "tool_use", "tool-call":
                let name = normalizedText(chunk["name"]) ?? "Tool"
                let inputText = stringify(chunk["input"])
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .toolCall,
                        title: "Tool call: \(name)",
                        body: inputText
                    )
                )
            case "tool_result", "tool-call-result":
                let outputText = stringifyToolResultContent(chunk["content"] ?? chunk["output"])
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .toolResult,
                        title: "Tool result",
                        body: outputText
                    )
                )
            default:
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .raw,
                        title: "Chunk \(type)",
                        body: stringify(chunk)
                    )
                )
            }
        }
        return entries
    }

    private static func parseOutputUserMessage(
        _ messageValue: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let message = messageValue as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-output-user",
                    role: .user,
                    kind: .raw,
                    title: "User output",
                    body: stringify(messageValue)
                )
            ]
        }

        if let contentString = normalizedText(message["content"]) {
            return [
                makeEntry(
                    id: "\(messageID)-output-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: contentString
                )
            ]
        }

        if let contentArray = message["content"] as? [Any], !contentArray.isEmpty {
            var entries: [SessionTranscriptEntry] = []
            for (index, item) in contentArray.enumerated() {
                if let chunk = item as? [String: Any], (chunk["type"] as? String) == "tool_result" {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-output-user-\(index)",
                            role: .agent,
                            kind: .toolResult,
                            title: "Tool result",
                            body: stringifyToolResultContent(chunk["content"])
                        )
                    )
                } else {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-output-user-\(index)",
                            role: .agent,
                            kind: .raw,
                            title: "Chunk",
                            body: stringify(item)
                        )
                    )
                }
            }
            return entries
        }

        return [
            makeEntry(
                id: "\(messageID)-output-user",
                role: .user,
                kind: .raw,
                title: "User output",
                body: stringify(message)
            )
        ]
    }

    private static func parseEventEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        if let dictionary = data as? [String: Any] {
            let type = normalizedText(dictionary["type"]) ?? "event"
            let body: String
            if let text = normalizedText(dictionary["message"]) {
                body = text
            } else {
                body = stringify(dictionary)
            }
            return [
                makeEntry(
                    id: "\(messageID)-event",
                    role: .system,
                    kind: .event,
                    title: type.replacingOccurrences(of: "_", with: " ").capitalized,
                    body: body
                )
            ]
        }
        return [
            makeEntry(
                id: "\(messageID)-event",
                role: .system,
                kind: .event,
                title: "Event",
                body: stringify(data)
            )
        ]
    }

    private static func parseACPEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let dictionary = data as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-acp",
                    role: .agent,
                    kind: .raw,
                    title: "Agent output",
                    body: stringify(data)
                )
            ]
        }

        let type = normalizedText(dictionary["type"]) ?? "unknown"
        switch type {
        case "message", "reasoning":
            let text = normalizedText(dictionary["message"]) ?? stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-\(type)",
                    role: .agent,
                    kind: .text,
                    title: type == "reasoning" ? "Reasoning" : nil,
                    body: text
                )
            ]
        case "thinking":
            let text = normalizedText(dictionary["text"]) ?? normalizedText(dictionary["message"]) ?? stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-thinking",
                    role: .agent,
                    kind: .thinking,
                    title: "Thinking",
                    body: text
                )
            ]
        case "tool-call":
            let name = normalizedText(dictionary["name"]) ?? "Tool"
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-call",
                    role: .agent,
                    kind: .toolCall,
                    title: "Tool call: \(name)",
                    body: stringify(dictionary["input"])
                )
            ]
        case "tool-result", "tool-call-result":
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-result",
                    role: .agent,
                    kind: .toolResult,
                    title: "Tool result",
                    body: stringifyToolResultContent(dictionary["output"] ?? dictionary["content"])
                )
            ]
        case "terminal-output":
            return [
                makeEntry(
                    id: "\(messageID)-acp-terminal",
                    role: .agent,
                    kind: .toolResult,
                    title: "Terminal output",
                    body: stringifyToolResultContent(dictionary["data"] ?? dictionary["output"])
                )
            ]
        case "permission-request":
            let tool = normalizedText(dictionary["toolName"]) ?? "Tool"
            let description = normalizedText(dictionary["description"]) ?? stringify(dictionary["options"])
            return [
                makeEntry(
                    id: "\(messageID)-acp-permission",
                    role: .system,
                    kind: .event,
                    title: "Approval needed: \(tool)",
                    body: description
                )
            ]
        case "task_started", "task_complete", "turn_aborted":
            return [
                makeEntry(
                    id: "\(messageID)-acp-task",
                    role: .system,
                    kind: .event,
                    title: type.replacingOccurrences(of: "_", with: " ").capitalized,
                    body: stringify(dictionary)
                )
            ]
        case "token_count":
            return []
        default:
            return [
                makeEntry(
                    id: "\(messageID)-acp-raw",
                    role: .agent,
                    kind: .raw,
                    title: "Agent \(type)",
                    body: stringify(dictionary)
                )
            ]
        }
    }

    private static func makeEntry(
        id: String,
        role: SessionTranscriptEntryRole,
        kind: SessionTranscriptEntryKind,
        title: String?,
        body: String
    ) -> SessionTranscriptEntry {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? " " : trimBody(trimmed)
        return SessionTranscriptEntry(
            id: id,
            role: role,
            kind: kind,
            title: title,
            body: normalized
        )
    }

    private static func trimBody(_ value: String) -> String {
        guard value.count > entryBodyLimit else { return value }
        return String(value.prefix(entryBodyLimit)) + "\n…"
    }

    private static func normalizedText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func stringifyToolResultContent(_ value: Any?) -> String {
        if let string = normalizedText(value) {
            return string
        }
        if let chunks = value as? [[String: Any]] {
            let texts = chunks.compactMap { chunk -> String? in
                guard (chunk["type"] as? String) == "text" else { return nil }
                return normalizedText(chunk["text"])
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        return stringify(value)
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private static func decodePayloadString(
        content: APIEncryptedMessageContent?,
        dataEncryptionKey: String?
    ) -> String? {
        guard let content else { return nil }
        let payload = content.c
        if content.t.lowercased() != "encrypted" {
            return payload
        }

        if let decrypted = decryptDataKeyPayload(
            payload: payload,
            dataEncryptionKey: dataEncryptionKey
        ),
           let text = String(data: decrypted, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        if let decoded = decodeBase64(payload),
           let text = String(data: decoded, encoding: .utf8) {
            return text
        }

        return payload
    }

    private static func decryptDataKeyPayload(
        payload: String,
        dataEncryptionKey: String?
    ) -> Data? {
        guard let dataEncryptionKey else { return nil }
        guard let keyData = decodeBase64(dataEncryptionKey), keyData.count == 32 else {
            return nil
        }
        guard let bundle = decodeBase64(payload) else {
            return nil
        }
        guard bundle.count >= (1 + 12 + 16), bundle.first == 0 else {
            return nil
        }

        let nonceData = bundle.subdata(in: 1..<13)
        let tagData = bundle.suffix(16)
        let ciphertextData = bundle.subdata(in: 13..<(bundle.count - 16))

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertextData,
                tag: tagData
            )
            let key = SymmetricKey(data: keyData)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            return nil
        }
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        if let direct = Data(base64Encoded: raw) {
            return direct
        }
        let replaced = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - (replaced.count % 4)) % 4
        let padded = replaced + String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: padded)
    }
}
