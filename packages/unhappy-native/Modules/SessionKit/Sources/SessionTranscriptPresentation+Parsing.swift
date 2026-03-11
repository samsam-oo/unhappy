import Foundation
import CoreKit

extension SessionTranscriptPresentationBuilder {
    private static let entryBodyLimit = 8_000
    private static let ansiEscapePattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
    private static let ansiEscapeRegex = try? NSRegularExpression(pattern: ansiEscapePattern)
    private static let removableControlCharacters: CharacterSet = {
        var set = CharacterSet.controlCharacters
        set.remove(charactersIn: "\n\t")
        return set
    }()

    public static func parseEntries(
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
        if let contentArray = record["content"] as? [Any], !contentArray.isEmpty {
            let entries = parseUserContentArray(contentArray, messageID: messageID)
            if !entries.isEmpty {
                return entries
            }
        }

        guard let content = record["content"] as? [String: Any] else {
            if let text = normalizedText(record["content"]) {
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
                    kind: .text,
                    title: nil,
                    body: stringify(record["content"])
                )
            ]
        }

        if let nestedContentArray = content["content"] as? [Any], !nestedContentArray.isEmpty {
            let entries = parseUserContentArray(nestedContentArray, messageID: messageID)
            if !entries.isEmpty {
                return entries
            }
        }

        if let type = (content["type"] as? String)?.lowercased() {
            switch type {
            case "text", "input_text":
                let text =
                    normalizedText(content["text"]) ??
                    normalizedText(content["input_text"]) ??
                    extractMessageText(from: content["content"]) ??
                    stringify(content)
                return [
                    makeEntry(
                        id: "\(messageID)-user",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                ]
            case "image", "input_image", "image_url":
                return [
                    makeEntry(
                        id: "\(messageID)-user-image-0",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: imagePlaceholderText(index: 1),
                        attachmentDataURL: extractImageDataURL(from: content)
                    )
                ]
            default:
                break
            }
        }

        if let text =
            extractMessageText(from: content["text"]) ??
            extractMessageText(from: content["message"]) ??
            extractMessageText(from: content["content"]) {
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

    static func makeEntry(
        id: String,
        role: SessionTranscriptEntryRole,
        kind: SessionTranscriptEntryKind,
        title: String?,
        body: String,
        attachmentDataURL: String? = nil,
        toolUseID: String? = nil,
        sourceType: String? = nil,
        preserveWhitespace: Bool = false,
        toolName: String? = nil,
        isSidechain: Bool = false,
        threadID: String? = nil
    ) -> SessionTranscriptEntry {
        let cleanedBody = sanitizeText(body)
        let normalizedBody: String = {
            if preserveWhitespace {
                if cleanedBody.isEmpty {
                    return " "
                }
                return trimBody(cleanedBody)
            }
            let trimmed = cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? " " : trimBody(trimmed)
        }()
        let cleanedTitle = title.map(sanitizeText)
        let cleanedSourceType = sourceType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSourceType = cleanedSourceType?.isEmpty == false
            ? cleanedSourceType
            : nil
        let cleanedToolName = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedToolName = cleanedToolName?.isEmpty == false
            ? cleanedToolName
            : nil
        let cleanedThreadID = threadID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThreadID = cleanedThreadID?.isEmpty == false
            ? cleanedThreadID
            : nil
        return SessionTranscriptEntry(
            id: id,
            role: role,
            kind: kind,
            title: cleanedTitle,
            body: normalizedBody,
            attachmentDataURL: normalizedImageDataURL(attachmentDataURL),
            toolUseID: toolUseID,
            sourceType: normalizedSourceType,
            toolName: normalizedToolName,
            isSidechain: isSidechain,
            threadID: normalizedThreadID
        )
    }

    static func extractIsSidechain(from dictionary: [String: Any]) -> Bool {
        if let explicit = dictionary["isSidechain"] as? Bool, explicit {
            return true
        }
        if let explicit = dictionary["sidechain"] as? Bool, explicit {
            return true
        }
        return normalizedText(dictionary["parent_tool_use_id"]) != nil ||
            normalizedText(dictionary["parentToolUseId"]) != nil
    }

    static func extractThreadID(from dictionary: [String: Any]) -> String? {
        return normalizedText(dictionary["thread_id"]) ??
            normalizedText(dictionary["threadId"]) ??
            normalizedText(dictionary["session_id"]) ??
            normalizedText(dictionary["sessionId"])
    }

    static func extractToolUseID(from dictionary: [String: Any]) -> String? {
        let candidates: [Any?] = [
            dictionary["tool_use_id"],
            dictionary["toolUseId"],
            dictionary["callId"],
            dictionary["id"],
        ]
        for candidate in candidates {
            if let text = normalizedText(candidate) {
                return text
            }
        }
        return nil
    }

    static func shouldDisplay(entry: SessionTranscriptEntry) -> Bool {
        let hasTitle = !(entry.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasBody = !entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle || hasBody
    }

    private static func trimBody(_ value: String) -> String {
        guard value.count > entryBodyLimit else { return value }
        return String(value.prefix(entryBodyLimit)) + "\n…"
    }

    static func normalizedText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let cleaned = sanitizeText(text)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func stringifyToolResultContent(_ value: Any?) -> String {
        if let string = extractMessageText(from: value) {
            return string
        }
        if let chunks = value as? [[String: Any]] {
            let texts = chunks.compactMap { chunk -> String? in
                guard let type = (chunk["type"] as? String)?.lowercased() else { return nil }
                guard type == "text" || type == "output_text" || type == "input_text" else { return nil }
                return normalizedText(chunk["text"])
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        return stringify(value)
    }

    static func shouldHideToolResult(_ value: Any?) -> Bool {
        guard let object = value as? [String: Any] else { return false }
        let status = normalizedText(object["status"])?.lowercased()
        let contentText = extractMessageText(from: object["content"])
        if status == "completed", contentText == nil {
            return true
        }
        return false
    }

    static func codexReasoningTitle(from value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        guard let title = normalizedText(object["title"]) else { return nil }
        return title
    }

    private static func parseUserContentArray(
        _ contentArray: [Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        var entries: [SessionTranscriptEntry] = []
        entries.reserveCapacity(contentArray.count)
        var imageIndex = 0

        for (index, item) in contentArray.enumerated() {
            guard let chunk = item as? [String: Any] else {
                if let text = normalizedText(item) {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: text
                        )
                    )
                } else {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .raw,
                            title: "Chunk",
                            body: stringify(item)
                        )
                    )
                }
                continue
            }

            let type = (normalizedText(chunk["type"]) ?? "").lowercased()
            switch type {
            case "text", "input_text":
                let text =
                    normalizedText(chunk["text"]) ??
                    normalizedText(chunk["input_text"]) ??
                    extractMessageText(from: chunk["content"]) ??
                    stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-user-\(index)",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                )
            case "image", "input_image", "image_url":
                imageIndex += 1
                entries.append(
                    makeEntry(
                        id: "\(messageID)-user-\(index)",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: imagePlaceholderText(index: imageIndex),
                        attachmentDataURL: extractImageDataURL(from: chunk)
                    )
                )
            default:
                if type.contains("image") {
                    imageIndex += 1
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: imagePlaceholderText(index: imageIndex),
                            attachmentDataURL: extractImageDataURL(from: chunk)
                        )
                    )
                    continue
                }

                if let text =
                    extractMessageText(from: chunk["text"]) ??
                    extractMessageText(from: chunk["message"]) ??
                    extractMessageText(from: chunk["content"]) {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: text
                        )
                    )
                } else {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .raw,
                            title: type.isEmpty ? "Chunk" : "Chunk \(type)",
                            body: stringify(chunk)
                        )
                    )
                }
            }
        }

        return entries
    }

    static func imagePlaceholderText(index: Int) -> String {
        "[Image #\(max(1, index))]"
    }

    static func extractImageDataURL(from dictionary: [String: Any]) -> String? {
        if let imageURL = normalizedText(dictionary["image_url"]) {
            return normalizedImageDataURL(imageURL)
        }
        if let imageURL = normalizedText(dictionary["imageUrl"]) {
            return normalizedImageDataURL(imageURL)
        }
        if let url = normalizedText(dictionary["url"]) {
            return normalizedImageDataURL(url)
        }
        if let source = dictionary["source"] as? [String: Any] {
            return extractImageDataURL(from: source)
        }
        return nil
    }

    static func normalizedImageDataURL(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("data:image/") || trimmed.hasPrefix("/") {
            return trimmed
        }
        return nil
    }

    static func sanitizeText(_ value: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if let regex = ansiEscapeRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        let scalars = cleaned.unicodeScalars.filter { scalar in
            !removableControlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func extractMessageText(from value: Any?) -> String? {
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

    public static func toolDisplayName(_ rawName: String) -> String {
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
        case "spawnagent":
            return "Spawn Agent"
        case "wait":
            return "Wait for Agent"
        case "writestdin", "sendinput":
            return "Send Input"
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

    public static func stringify(_ value: Any?) -> String {
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
}
