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
    private static let accountSecretDefaultsKey = "unhappy.native.account.secret"
    private static let payloadBundleVersion: UInt8 = 2
    private static let wrappedDataKeyBundleVersion: UInt8 = 2
    private static let x25519PublicKeyLength = 32
    private static let aesGCMNonceLength = 12
    private static let aesGCMTagLength = 16
    private static let minimumPayloadBundleLength = 1 + aesGCMNonceLength + aesGCMTagLength
    private static let minimumWrappedDataKeyBundleLength =
        1 + x25519PublicKeyLength + aesGCMNonceLength + aesGCMTagLength
    private static let wrappedDataKeyKDFSalt =
        Data("unhappy.data.encryption-key.wrap.salt.v2".utf8)
    private static let wrappedDataKeyKDFInfo =
        Data("unhappy.data.encryption-key.wrap.info.v2".utf8)

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
                        title: toolDisplayName(name),
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
            let type = (normalizedText(dictionary["type"]) ?? "event").lowercased()
            let messageText = normalizedText(dictionary["message"])
            if type == "ready" {
                return []
            }
            let body = messageText ?? stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-event",
                    role: .system,
                    kind: .event,
                    title: type == "message"
                        ? nil
                        : type.replacingOccurrences(of: "_", with: " ").capitalized,
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
            let text =
                extractMessageText(from: dictionary["message"]) ??
                extractMessageText(from: dictionary["text"]) ??
                extractMessageText(from: dictionary["content"]) ??
                stringify(dictionary)
            if type == "message",
               text.hasPrefix("Existing Codex sessions for this project:") {
                return []
            }
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
                    title: toolDisplayName(name),
                    body: stringify(dictionary["input"])
                )
            ]
        case "tool-result", "tool-call-result":
            let name = normalizedText(dictionary["name"])
            let title = name.map { "\(toolDisplayName($0)) Result" } ?? "Tool Result"
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-result",
                    role: .agent,
                    kind: .toolResult,
                    title: title,
                    body: stringifyToolResultContent(dictionary["output"] ?? dictionary["content"])
                )
            ]
        case "terminal-output":
            return [
                makeEntry(
                    id: "\(messageID)-acp-terminal",
                    role: .agent,
                    kind: .toolResult,
                    title: "Run Command Output",
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
        if let string = extractMessageText(from: value) {
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

    private static func extractMessageText(from value: Any?) -> String? {
        guard let value else { return nil }
        if let text = normalizedText(value) {
            return text
        }
        if let dictionary = value as? [String: Any] {
            let directCandidates: [Any?] = [
                dictionary["text"],
                dictionary["message"],
                dictionary["delta"],
                dictionary["content"],
                dictionary["output"],
            ]
            for candidate in directCandidates {
                if let extracted = extractMessageText(from: candidate) {
                    return extracted
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { extractMessageText(from: $0) }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return nil
    }

    private static func toolDisplayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tool" }
        let key = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch key {
        case "read", "readfile", "readfiles":
            return "Read Files"
        case "write", "writefile", "writefiles", "edit", "applypatch", "codexpatch", "patch":
            return "Edit Files"
        case "bash", "codexbash", "execcommand", "terminal", "shell":
            return "Run Command"
        case "listdirectory", "getdirectorytree", "ls":
            return "List Files"
        case "ripgrep", "rg", "grep", "search":
            return "Search Files"
        case "difftastic", "diff":
            return "View Diff"
        case "task":
            return "Run Task"
        case "webfetch":
            return "Fetch Web"
        case "codexreasoning":
            return "Reasoning"
        default:
            return humanizedIdentifier(trimmed)
        }
    }

    private static func humanizedIdentifier(_ value: String) -> String {
        let separatorsNormalized = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let withCamelSpacing = separatorsNormalized.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        let collapsed = withCamelSpacing
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "Tool" }
        return collapsed
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                return lower.prefix(1).uppercased() + String(lower.dropFirst())
            }
            .joined(separator: " ")
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

        if let resolvedDataKey = resolveDataEncryptionKey(raw: dataEncryptionKey),
           let decrypted = decryptDataKeyPayload(
            payload: payload,
            keyData: resolvedDataKey
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

    private static func resolveDataEncryptionKey(raw: String?) -> Data? {
        guard let raw else { return nil }
        guard let decoded = decodeBase64(raw) else { return nil }
        guard
            let accountSecret = loadAccountSecret(),
            let contentSecret = deriveContentBoxSecretKey(fromAccountSecret: accountSecret)
        else {
            return nil
        }
        return decryptWrappedDataKey(bundle: decoded, secretKey: contentSecret)
    }

    private static func decryptWrappedDataKey(bundle: Data, secretKey: Data) -> Data? {
        guard
            secretKey.count == x25519PublicKeyLength,
            bundle.count >= minimumWrappedDataKeyBundleLength,
            bundle.first == wrappedDataKeyBundleVersion
        else {
            return nil
        }

        let ephemeralStart = 1
        let ephemeralEnd = ephemeralStart + x25519PublicKeyLength
        let nonceStart = ephemeralEnd
        let nonceEnd = nonceStart + aesGCMNonceLength

        let ephemeralPublicKeyData = bundle.subdata(in: ephemeralStart..<ephemeralEnd)
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let encryptedAndTag = bundle.suffix(from: nonceEnd)
        guard encryptedAndTag.count >= aesGCMTagLength else {
            return nil
        }

        let ciphertextData = encryptedAndTag.dropLast(aesGCMTagLength)
        let tagData = encryptedAndTag.suffix(aesGCMTagLength)

        do {
            let recipientPrivateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: secretKey
            )
            let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: ephemeralPublicKeyData
            )
            let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
                with: ephemeralPublicKey
            )
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: wrappedDataKeyKDFSalt,
                sharedInfo: wrappedDataKeyKDFInfo,
                outputByteCount: 32
            )
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertextData),
                tag: Data(tagData)
            )
            let opened = try AES.GCM.open(sealed, using: symmetricKey)
            return opened.count == 32 ? opened : nil
        } catch {
            return nil
        }
    }

    private static func decryptDataKeyPayload(
        payload: String,
        keyData: Data
    ) -> Data? {
        guard keyData.count == 32 else {
            return nil
        }
        guard let bundle = decodeBase64(payload) else {
            return nil
        }
        guard
            bundle.count >= minimumPayloadBundleLength,
            bundle.first == payloadBundleVersion
        else {
            return nil
        }

        let nonceStart = 1
        let nonceEnd = nonceStart + aesGCMNonceLength
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let encryptedAndTag = bundle.suffix(from: nonceEnd)
        guard encryptedAndTag.count >= aesGCMTagLength else {
            return nil
        }

        let ciphertextData = encryptedAndTag.dropLast(aesGCMTagLength)
        let tagData = encryptedAndTag.suffix(aesGCMTagLength)

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertextData),
                tag: Data(tagData)
            )
            let key = SymmetricKey(data: keyData)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            return nil
        }
    }

    private static func loadAccountSecret() -> Data? {
        let raw = UserDefaults.standard
            .string(forKey: accountSecretDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        guard let decoded = decodeBase64(raw), decoded.count == 32 else {
            return nil
        }
        return decoded
    }

    private static func deriveContentBoxSecretKey(fromAccountSecret accountSecret: Data) -> Data? {
        guard accountSecret.count == 32 else { return nil }
        guard let contentSeed = deriveKey(
            master: accountSecret,
            usage: "Unhappy EnCoder",
            path: ["content"]
        ) else {
            return nil
        }
        return deriveCurve25519SecretKey(fromSeed: contentSeed)
    }

    private static func deriveKey(master: Data, usage: String, path: [String]) -> Data? {
        let rootInput = Data("\(usage) Master Seed".utf8)
        let rootDigest = hmacSHA512(key: master, data: rootInput)
        guard rootDigest.count == 64 else { return nil }

        var key = Data(rootDigest.prefix(32))
        var chainCode = Data(rootDigest.suffix(32))
        for index in path {
            var childInput = Data([0x00])
            childInput.append(Data(index.utf8))
            let childDigest = hmacSHA512(key: chainCode, data: childInput)
            guard childDigest.count == 64 else { return nil }
            key = Data(childDigest.prefix(32))
            chainCode = Data(childDigest.suffix(32))
        }
        return key
    }

    private static func hmacSHA512(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA512>.authenticationCode(
            for: data,
            using: SymmetricKey(data: key)
        )
        return Data(mac)
    }

    private static func deriveCurve25519SecretKey(fromSeed seed: Data) -> Data? {
        guard seed.count == 32 else { return nil }
        let digest = SHA512.hash(data: seed)
        var scalar = Array(digest.prefix(32))
        guard scalar.count == 32 else { return nil }

        scalar[0] &= 248
        scalar[31] &= 127
        scalar[31] |= 64
        return Data(scalar)
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
