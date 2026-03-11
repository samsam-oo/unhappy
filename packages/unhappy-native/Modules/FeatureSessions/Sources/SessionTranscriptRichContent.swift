import Foundation
import SwiftUI
import CoreKit
import UIFoundation

struct SessionTranscriptGenericToolField: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
}

struct SessionTranscriptPlanStepPresentation: Equatable, Identifiable, Sendable {
    enum Status: String, Equatable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed

        var label: String {
            switch self {
            case .pending:
                return "Planned"
            case .inProgress:
                return "In Progress"
            case .completed:
                return "Completed"
            }
        }

        var symbolName: String {
            switch self {
            case .pending:
                return "circle"
            case .inProgress:
                return "circle.dotted"
            case .completed:
                return "checkmark.circle.fill"
            }
        }
    }

    let id: String
    let step: String
    let status: Status
}

struct SessionTranscriptGenericToolPresentation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case plan
        case spawnAgent
        case wait
        case stdin
        case toolResult
        case toolCall
    }

    enum BadgeTone: Equatable, Sendable {
        case accent
        case success
        case warning
        case neutral
    }

    let kind: Kind
    let title: String
    let compactSummary: String?
    let subtitle: String?
    let badgeText: String?
    let badgeTone: BadgeTone
    let fields: [SessionTranscriptGenericToolField]
    let body: String?
    let planItems: [SessionTranscriptPlanStepPresentation]
}

struct SessionMarkdownListItem: Equatable, Sendable {
    let depth: Int
    let marker: String
    let text: String
}

enum SessionMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case code(language: String?, code: String)
    case list([SessionMarkdownListItem])
    case image(altText: String, source: String)
}

enum SessionTranscriptFileChangeKind: String, Equatable, Sendable {
    case added
    case deleted
    case modified
    case moved
    case unknown

    var label: String {
        switch self {
        case .added:
            return "Added"
        case .deleted:
            return "Deleted"
        case .modified:
            return "Updated"
        case .moved:
            return "Moved"
        case .unknown:
            return "Changed"
        }
    }

    var tint: Color {
        switch self {
        case .added:
            return .green
        case .deleted:
            return .red
        case .modified:
            return AppPalette.accent
        case .moved:
            return .orange
        case .unknown:
            return AppPalette.secondaryText
        }
    }

    var iconSystemName: String {
        switch self {
        case .added:
            return "plus"
        case .deleted:
            return "trash"
        case .modified:
            return "pencil"
        case .moved:
            return "arrow.right"
        case .unknown:
            return "circle.fill"
        }
    }
}

struct SessionTranscriptDiffLinePresentation: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case added
        case removed
        case context
        case meta
    }

    let id: String
    let kind: Kind
    let text: String
}

struct SessionTranscriptDiffHunkPresentation: Equatable, Identifiable, Sendable {
    let id: String
    let header: String
    let lines: [SessionTranscriptDiffLinePresentation]
}

struct SessionTranscriptDiffFilePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let hunkCount: Int
    let preview: String
    let patch: String
    let hunks: [SessionTranscriptDiffHunkPresentation]
}

struct SessionTranscriptFileChangePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let kind: SessionTranscriptFileChangeKind
    let movePath: String?
    let summary: String?
    let diffFiles: [SessionTranscriptDiffFilePresentation]
}

struct SessionTranscriptCommandExecutionPayload: Equatable, Sendable {
    struct SupplementalEntry: Equatable, Identifiable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case stdin
            case toolResult
        }

        let id: String
        let kind: Kind
        let title: String
        let body: String
    }

    let command: String?
    let cwd: String?
    let summary: String?
    let logs: String?
    let stdout: String?
    let stderr: String?
    let sessionID: String?
    let success: Bool?
    let exitCode: Int?
    let status: String?
    let durationMs: Int?
    let supplementalEntries: [SupplementalEntry]

    init(
        command: String?,
        cwd: String?,
        summary: String?,
        logs: String?,
        stdout: String?,
        stderr: String?,
        sessionID: String? = nil,
        success: Bool?,
        exitCode: Int?,
        status: String?,
        durationMs: Int?,
        supplementalEntries: [SupplementalEntry]
    ) {
        self.command = command
        self.cwd = cwd
        self.summary = summary
        self.logs = logs
        self.stdout = stdout
        self.stderr = stderr
        self.sessionID = sessionID
        self.success = success
        self.exitCode = exitCode
        self.status = status
        self.durationMs = durationMs
        self.supplementalEntries = supplementalEntries
    }

    var displayedLogs: String? {
        let normalizedLogs = logs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStdout = stdout?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStderr = stderr?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedLogs, !normalizedLogs.isEmpty {
            if let normalizedStderr,
               !normalizedStderr.isEmpty,
               normalizedLogs.contains(normalizedStderr) == false {
                return normalizedLogs + "\n" + normalizedStderr
            }
            return normalizedLogs
        }

        let parts = [normalizedStdout, normalizedStderr]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }
}

struct SessionTranscriptCommandRunPresentation: Equatable, Sendable {
    enum StatusTone: Equatable, Sendable {
        case running
        case success
        case failure
    }

    enum Status: Equatable, Sendable {
        case running
        case succeeded
        case failed

        var badgeLabel: String {
            switch self {
            case .running:
                return "Running"
            case .succeeded:
                return "Success"
            case .failed:
                return "Failed"
            }
        }

        var tone: StatusTone {
            switch self {
            case .running:
                return .running
            case .succeeded:
                return .success
            case .failed:
                return .failure
            }
        }
    }

    let command: String
    let cwd: String?
    let summary: String?
    let logs: String?
    let status: Status
    let exitCode: Int?
    let durationText: String?
    let supplementalEntries: [SessionTranscriptCommandExecutionPayload.SupplementalEntry]

    var hasExpandableDetails: Bool {
        true
    }

    var waitingDescription: String {
        if let summary, !summary.isEmpty {
            return summary
        }
        if let cwd, !cwd.isEmpty {
            return "Working in \(cwd)"
        }
        return "Waiting for command output…"
    }
}

enum SessionTranscriptRichToolContent: Equatable, Sendable {
    case commandExecution(SessionTranscriptCommandRunPresentation)
    case fileChanges([SessionTranscriptFileChangePresentation])
    case diff([SessionTranscriptDiffFilePresentation])
    case toolDetails(SessionTranscriptGenericToolPresentation)
}

enum SessionTranscriptRichContentParser {
    static func markdownBlocks(from raw: String) -> [SessionMarkdownBlock] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        var blocks: [SessionMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = trimmed.count > 3
                    ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(
                    .code(
                        language: language.isEmpty ? nil : language,
                        code: codeLines.joined(separator: "\n")
                    )
                )
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let image = parseMarkdownImage(trimmed) {
                blocks.append(.image(altText: image.altText, source: image.source))
                index += 1
                continue
            }

            if isQuoteLine(trimmed) {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isQuoteLine(candidate) else { break }
                    quoteLines.append(stripQuotePrefix(candidate))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if parseListItem(line) != nil {
                var items: [SessionMarkdownListItem] = []
                while index < lines.count {
                    guard let item = parseListItem(lines[index]) else { break }
                    items.append(item)
                    index += 1
                }
                if !items.isEmpty {
                    blocks.append(.list(items))
                }
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty ||
                    candidateTrimmed.hasPrefix("```") ||
                    parseHeading(candidateTrimmed) != nil ||
                    parseMarkdownImage(candidateTrimmed) != nil ||
                    isQuoteLine(candidateTrimmed) ||
                    parseListItem(candidate) != nil {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            } else {
                index += 1
            }
        }

        return blocks.isEmpty ? [.paragraph(raw)] : blocks
    }

    static func richToolContent(for entry: SessionTranscriptEntry) -> SessionTranscriptRichToolContent? {
        if let command = commandPresentation(for: entry) {
            return .commandExecution(command)
        }
        if let fileChanges = parseFileChanges(from: entry.body), !fileChanges.isEmpty {
            return .fileChanges(fileChanges)
        }
        if let diffFiles = parseUnifiedDiffFiles(from: entry.body, fallbackPath: fallbackDiffPath(for: entry)),
           !diffFiles.isEmpty {
            return .diff(diffFiles)
        }
        if let toolDetails = genericToolPresentation(for: entry) {
            return .toolDetails(toolDetails)
        }
        return nil
    }

    static func userInputPresentation(
        for entry: SessionTranscriptEntry
    ) -> SessionTranscriptGenericToolPresentation? {
        guard case .toolDetails(let tool)? = richToolContent(for: entry),
              tool.kind == .stdin,
              let body = tool.body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else {
            return nil
        }
        return tool
    }

    static func summaryTitle(for entry: SessionTranscriptEntry) -> String? {
        if let richContent = richToolContent(for: entry) {
            switch richContent {
            case .commandExecution(let command):
                if let summary = command.summary, !summary.isEmpty {
                    return summary
                }
                return "Ran command"
            case .fileChanges(let changes):
                if changes.count == 1, let first = changes.first {
                    return "\(first.kind.label) \(fileName(from: first.path))"
                }
                return "Edited \(changes.count) files"
            case .diff(let files):
                return diffSummaryTitle(files)
            case .toolDetails(let tool):
                if let compactSummary = tool.compactSummary, !compactSummary.isEmpty {
                    return "\(tool.title) · \(compactSummary)"
                }
                return tool.title
            }
        }

        guard entry.kind == .toolCall || entry.kind == .toolResult else {
            return nil
        }
        let normalizedToolName = entry.toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedToolName == "codexbash" ||
                normalizedToolName == "bash" ||
                normalizedToolName == "exec_command" else {
            return nil
        }
        return commandSummaryText(from: entry.body)
    }

    static func summarySubtitle(for entry: SessionTranscriptEntry) -> String? {
        guard let richContent = richToolContent(for: entry) else {
            return nil
        }

        switch richContent {
        case .commandExecution(let command):
            if let summary = command.summary, !summary.isEmpty {
                return summary
            }
            return command.command
        case .fileChanges(let changes):
            guard changes.count == 1, let first = changes.first else { return nil }
            return first.path
        case .diff(let files):
            return diffSummarySubtitle(files)
        case .toolDetails(let tool):
            return tool.subtitle
        }
    }

    static func commandPayload(for entry: SessionTranscriptEntry) -> SessionTranscriptCommandExecutionPayload? {
        commandPayload(from: entry.body)
    }

    static func encodeCommandPayload(_ payload: SessionTranscriptCommandExecutionPayload) -> String {
        var object: [String: Any] = [
            "type": "commandExecutionPresentation"
        ]
        if let command = payload.command, !command.isEmpty {
            object["command"] = command
        }
        if let cwd = payload.cwd, !cwd.isEmpty {
            object["cwd"] = cwd
        }
        if let summary = payload.summary, !summary.isEmpty {
            object["summary"] = summary
        }
        if let logs = payload.logs, !logs.isEmpty {
            object["logs"] = logs
        }
        if let stdout = payload.stdout, !stdout.isEmpty {
            object["stdout"] = stdout
        }
        if let stderr = payload.stderr, !stderr.isEmpty {
            object["stderr"] = stderr
        }
        if let sessionID = payload.sessionID, !sessionID.isEmpty {
            object["sessionId"] = sessionID
        }
        if let success = payload.success {
            object["success"] = success
        }
        if let exitCode = payload.exitCode {
            object["exitCode"] = exitCode
        }
        if let status = payload.status, !status.isEmpty {
            object["status"] = status
        }
        if let durationMs = payload.durationMs {
            object["durationMs"] = durationMs
        }
        if !payload.supplementalEntries.isEmpty {
            object["supplementalEntries"] = payload.supplementalEntries.map { item in
                [
                    "id": item.id,
                    "kind": item.kind.rawValue,
                    "title": item.title,
                    "body": item.body,
                ]
            }
        }

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func commandSummaryText(from rawBody: String) -> String? {
        commandSummary(from: rawBody)
    }

    static func attributedInlineMarkdown(_ raw: String) -> AttributedString? {
        let normalized = normalizeAppMentions(in: normalizeMarkdownLinks(in: raw))
        return try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }

    static func commandPresentation(
        for entry: SessionTranscriptEntry
    ) -> SessionTranscriptCommandRunPresentation? {
        guard let payload = commandPayload(from: entry.body) else {
            return nil
        }

        let command = payload.command?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let command, !command.isEmpty else {
            return nil
        }

        let normalizedStatus = payload.status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let status: SessionTranscriptCommandRunPresentation.Status = {
            if payload.success == false {
                return .failed
            }
            if payload.success == true {
                return .succeeded
            }
            if let normalizedStatus {
                if normalizedStatus.contains("fail") || normalizedStatus.contains("error") {
                    return .failed
                }
                if normalizedStatus.contains("complete") ||
                    normalizedStatus.contains("success") ||
                    normalizedStatus.contains("done") {
                    return .succeeded
                }
            }
            return entry.kind == .toolResult ? .succeeded : .running
        }()

        let cwd = payload.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines)

        return SessionTranscriptCommandRunPresentation(
            command: command,
            cwd: cwd?.isEmpty == false ? cwd : nil,
            summary: summary?.isEmpty == false ? summary : nil,
            logs: payload.displayedLogs,
            status: status,
            exitCode: payload.exitCode,
            durationText: formatCommandDuration(milliseconds: payload.durationMs),
            supplementalEntries: payload.supplementalEntries
        )
    }

    private static func commandPayload(from rawBody: String) -> SessionTranscriptCommandExecutionPayload? {
        guard let object = parseJSONObject(from: rawBody) else {
            return nil
        }

        let summary = normalizeString(object["summary"]) ?? commandSummary(from: rawBody)
        let command = normalizeString(object["command"]) ??
            normalizeString(object["cmd"]) ??
            extractCommand(from: object["commandActions"]) ??
            extractCommand(from: object["parsed_cmd"]) ??
            extractCommand(from: object["parsedCmd"])
        let cwd = normalizeString(object["cwd"])
        let logs = normalizeString(object["logs"])
        let stdout = normalizeString(object["stdout"]) ??
            normalizeString(object["aggregatedOutput"]) ??
            normalizeString(object["aggregated_output"]) ??
            normalizeString(object["formatted_output"]) ??
            normalizeString(object["output"])
        let stderr = normalizeString(object["stderr"]) ??
            normalizeString(object["error"])
        let sessionID = normalizeString(object["sessionId"]) ??
            normalizeString(object["session_id"])
        let success = normalizeBool(object["success"])
        let exitCode = normalizeInt(object["exitCode"]) ??
            normalizeInt(object["exit_code"]) ??
            normalizeInt(object["code"])
        let status = normalizeString(object["status"]) ??
            normalizeString(object["state"])
        let durationMs = normalizeInt(object["durationMs"]) ??
            normalizeInt(object["duration_ms"])
        let supplementalEntries: [SessionTranscriptCommandExecutionPayload.SupplementalEntry] = (
            object["supplementalEntries"] as? [[String: Any]] ?? []
        ).compactMap { item in
            guard
                let id = normalizeString(item["id"]),
                let rawKind = normalizeString(item["kind"]),
                let kind = SessionTranscriptCommandExecutionPayload.SupplementalEntry.Kind(rawValue: rawKind),
                let title = normalizeString(item["title"]),
                let body = normalizeString(item["body"])
            else {
                return nil
            }
            return .init(id: id, kind: kind, title: title, body: body)
        }

        guard [command, summary, logs, stdout, stderr, sessionID].contains(where: { $0?.isEmpty == false }) ||
                success != nil ||
                exitCode != nil ||
                status != nil ||
                durationMs != nil ||
                !supplementalEntries.isEmpty else {
            return nil
        }

        return SessionTranscriptCommandExecutionPayload(
            command: command,
            cwd: cwd,
            summary: summary,
            logs: logs,
            stdout: stdout,
            stderr: stderr,
            sessionID: sessionID,
            success: success,
            exitCode: exitCode,
            status: status,
            durationMs: durationMs,
            supplementalEntries: supplementalEntries
        )
    }

    static func genericToolPresentation(
        for entry: SessionTranscriptEntry
    ) -> SessionTranscriptGenericToolPresentation? {
        guard entry.kind == .toolCall || entry.kind == .toolResult else {
            return nil
        }
        guard let object = parseJSONObject(from: entry.body) else {
            return nil
        }

        let normalizedToolName = entry.toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let kind: SessionTranscriptGenericToolPresentation.Kind = {
            switch normalizedToolName {
            case "update_plan":
                return .plan
            case "spawn_agent":
                return .spawnAgent
            case "wait":
                return .wait
            case "write_stdin", "send_input":
                return .stdin
            default:
                return entry.kind == .toolResult ? .toolResult : .toolCall
            }
        }()

        let title: String
        switch kind {
        case .plan:
            title = "Plan"
        case .spawnAgent:
            title = "Spawn Agent"
        case .wait:
            title = "Wait for Agent"
        case .stdin:
            title = "User Input"
        case .toolResult:
            title = entry.title ?? "Tool Result"
        case .toolCall:
            title = entry.title ?? "Tool Call"
        }

        let compactSummary = genericToolCompactSummary(kind: kind, object: object)
        let subtitle = genericToolSubtitle(kind: kind, object: object)
        let badge = genericToolBadge(kind: kind, entryKind: entry.kind, object: object)
        let planItems = parsePlanItems(from: object["plan"]) ?? []

        let interestingKeys = Set([
            "agent_id",
            "id",
            "nickname",
            "agentNickname",
            "agent_type",
            "timeout_ms",
            "status",
            "completed",
            "timed_out",
            "session_id",
            "thread_id",
            "ids",
            "agent_ids",
        ])
        let fields: [SessionTranscriptGenericToolField] = Array(interestingKeys).sorted().enumerated().compactMap { index, key in
            guard let value = genericToolFieldValue(for: key, value: object[key]) else { return nil }
            return SessionTranscriptGenericToolField(
                id: "\(key)-\(index)",
                label: humanizedFieldName(key),
                value: value
            )
        }

        let body: String?
        switch kind {
        case .stdin:
            body = normalizeString(object["chars"]) ?? normalizeString(object["text"])
        case .plan:
            body = nil
        default:
            body = formattedGenericToolBody(
                object,
                excludingKeys: interestingKeys.union([
                    "message",
                    "prompt",
                    "description",
                    "explanation",
                    "plan",
                    "chars",
                    "text",
                ])
            )
        }

        if kind == .stdin, body?.isEmpty != false {
            return nil
        }

        let hasStructuredHighlights = compactSummary != nil ||
            subtitle != nil ||
            badge != nil ||
            !fields.isEmpty ||
            !planItems.isEmpty

        if !hasStructuredHighlights {
            return nil
        }

        return SessionTranscriptGenericToolPresentation(
            kind: kind,
            title: title,
            compactSummary: compactSummary,
            subtitle: subtitle,
            badgeText: badge?.text,
            badgeTone: badge?.tone ?? .neutral,
            fields: fields,
            body: body,
            planItems: planItems
        )
    }

    private static func extractCommand(from value: Any?) -> String? {
        if let text = normalizeString(value) {
            return text
        }
        if let actions = value as? [[String: Any]] {
            for action in actions {
                if let command = normalizeString(action["command"]) {
                    return command
                }
                if let command = normalizeString(action["cmd"]) {
                    return command
                }
            }
        }
        return nil
    }

    private static func formatCommandDuration(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let totalSeconds = milliseconds / 1_000
        if totalSeconds < 1 {
            let tenths = max(1, Int((Double(milliseconds) / 100.0).rounded()))
            return "\(Double(tenths) / 10.0)s"
        }
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let prefixCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(prefixCount) else { return nil }
        let remainder = line.dropFirst(prefixCount).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }
        return (prefixCount, remainder)
    }

    private static func parseMarkdownImage(_ line: String) -> (altText: String, source: String)? {
        let pattern = #"^!\[(.*?)\]\((.+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let altRange = Range(match.range(at: 1), in: line),
              let sourceRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let altText = String(line[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let source = String(line[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        return (altText, source)
    }

    private static func isQuoteLine(_ line: String) -> Bool {
        line.hasPrefix(">") || line.hasPrefix("&gt;")
    }

    private static func stripQuotePrefix(_ line: String) -> String {
        if line.hasPrefix("&gt;") {
            return String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func parseListItem(_ line: String) -> SessionMarkdownListItem? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let bulletMarkers = ["- ", "* ", "+ "]
        for marker in bulletMarkers where trimmed.hasPrefix(marker) {
            let text = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SessionMarkdownListItem(
                depth: max(0, indent / 2),
                marker: String(marker.trimmingCharacters(in: .whitespaces)),
                text: text
            )
        }

        let pieces = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2,
              Int(pieces[0]) != nil else {
            return nil
        }
        let text = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SessionMarkdownListItem(
            depth: max(0, indent / 2),
            marker: "\(pieces[0]).",
            text: text
        )
    }

    private static func parseFileChanges(from raw: String) -> [SessionTranscriptFileChangePresentation]? {
        guard let object = parseJSONObject(from: raw) else {
            return nil
        }

        let latestType = normalizeString(object["type"])?.lowercased()
        if latestType == "filechange",
           let latestChanges = object["changes"] as? [[String: Any]] {
            let presentations = latestChanges.compactMap { change -> SessionTranscriptFileChangePresentation? in
                guard let path = normalizeString(change["path"]) else { return nil }
                let kindObject = change["kind"] as? [String: Any]
                let movePath = normalizeString(kindObject?["move_path"] ?? change["move_path"])
                let kind = inferLatestChangeKind(kindObject, movePath: movePath)
                let embeddedDiff = firstString(change["diff"], change["unified_diff"], change["patch"])
                let diffFiles = embeddedDiff.flatMap {
                    parseUnifiedDiffFiles(from: $0, fallbackPath: movePath ?? path)
                } ?? []
                let summary = makeChangeSummary(
                    kind: kind,
                    oldText: nil,
                    newText: nil,
                    diffFiles: diffFiles
                )

                return SessionTranscriptFileChangePresentation(
                    id: path,
                    path: path,
                    kind: kind,
                    movePath: movePath,
                    summary: summary,
                    diffFiles: diffFiles
                )
            }

            return presentations.isEmpty ? nil : presentations
        }

        guard let changes = object["changes"] as? [String: Any] else {
            return nil
        }

        let presentations = changes.keys.sorted().compactMap { path -> SessionTranscriptFileChangePresentation? in
            guard let change = changes[path] as? [String: Any] else { return nil }

            let movePath = normalizeString(change["move_path"] ?? change["movePath"])
            let kind = inferChangeKind(from: change, movePath: movePath)
            let embeddedDiff = firstString(
                change["unified_diff"],
                change["diff"],
                change["patch"],
                change["raw_diff"],
                (change["modify"] as? [String: Any])?["unified_diff"],
                (change["modify"] as? [String: Any])?["diff"],
                (change["modify"] as? [String: Any])?["patch"]
            )
            let oldText = firstString(
                change["old_content"],
                change["oldText"],
                (change["modify"] as? [String: Any])?["old_content"]
            )
            let newText = firstString(
                change["new_content"],
                change["newText"],
                (change["modify"] as? [String: Any])?["new_content"],
                (change["add"] as? [String: Any])?["content"],
                (change["delete"] as? [String: Any])?["content"]
            )

            let diffFiles = embeddedDiff.flatMap {
                parseUnifiedDiffFiles(from: $0, fallbackPath: movePath ?? path)
            } ?? []

            let summary = makeChangeSummary(
                kind: kind,
                oldText: oldText,
                newText: newText,
                diffFiles: diffFiles
            )

            return SessionTranscriptFileChangePresentation(
                id: path,
                path: path,
                kind: kind,
                movePath: movePath,
                summary: summary,
                diffFiles: diffFiles
            )
        }

        return presentations.isEmpty ? nil : presentations
    }

    private static func parseUnifiedDiffFiles(
        from raw: String,
        fallbackPath: String?
    ) -> [SessionTranscriptDiffFilePresentation]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed = parseNamedDiffFiles(from: trimmed)
        if !parsed.isEmpty {
            return parsed
        }
        guard let fallbackPath else { return nil }
        return [makeStandaloneDiffFile(path: fallbackPath, patch: trimmed)]
    }

    private static func parseNamedDiffFiles(from rawDiff: String) -> [SessionTranscriptDiffFilePresentation] {
        let lines = rawDiff.components(separatedBy: .newlines)
        let blockStarts = lines.enumerated().compactMap { index, line in
            line.hasPrefix("diff --git ") ? index : nil
        }
        guard !blockStarts.isEmpty else { return [] }

        var files: [SessionTranscriptDiffFilePresentation] = []
        for (index, start) in blockStarts.enumerated() {
            let end = (index + 1 < blockStarts.count) ? blockStarts[index + 1] : lines.count
            guard start < end else { continue }
            let block = Array(lines[start..<end])
            let header = block.first ?? ""
            let parsedPath = parseDiffPath(fromHeader: header) ?? "file-\(index + 1)"
            files.append(makeDiffFile(path: parsedPath, patch: block.joined(separator: "\n"), fileIndex: index))
        }
        return files
    }

    private static func makeStandaloneDiffFile(path: String, patch: String) -> SessionTranscriptDiffFilePresentation {
        makeDiffFile(path: path, patch: patch, fileIndex: 0)
    }

    private static func makeDiffFile(path: String, patch: String, fileIndex: Int) -> SessionTranscriptDiffFilePresentation {
        let lines = patch.components(separatedBy: .newlines)
        let hunkCount = lines.filter { $0.hasPrefix("@@") }.count
        let preview = lines
            .filter { line in
                (line.hasPrefix("+") || line.hasPrefix("-")) &&
                !line.hasPrefix("+++") &&
                !line.hasPrefix("---")
            }
            .prefix(3)
            .joined(separator: "\n")
        let hunks = parseDiffHunks(from: lines, fileIndex: fileIndex, path: path)
        return SessionTranscriptDiffFilePresentation(
            id: "\(fileIndex)-\(path)",
            path: path,
            hunkCount: hunkCount,
            preview: preview.isEmpty ? "No line-level preview" : preview,
            patch: patch,
            hunks: hunks
        )
    }

    private static func parseDiffHunks(
        from lines: [String],
        fileIndex: Int,
        path: String
    ) -> [SessionTranscriptDiffHunkPresentation] {
        var hunks: [SessionTranscriptDiffHunkPresentation] = []
        var currentHeader: String?
        var currentLines: [SessionTranscriptDiffLinePresentation] = []
        var currentLineIndex = 0
        var hunkIndex = 0

        func appendCurrentHunkIfNeeded() {
            guard let currentHeader else { return }
            hunks.append(
                SessionTranscriptDiffHunkPresentation(
                    id: "\(fileIndex)-\(path)-h\(hunkIndex)",
                    header: currentHeader,
                    lines: currentLines
                )
            )
            hunkIndex += 1
        }

        for line in lines {
            if line.hasPrefix("@@") {
                appendCurrentHunkIfNeeded()
                currentHeader = line
                currentLineIndex = 0
                currentLines = [
                    SessionTranscriptDiffLinePresentation(
                        id: "\(fileIndex)-\(path)-h\(hunkIndex)-l\(currentLineIndex)",
                        kind: .meta,
                        text: line
                    )
                ]
                currentLineIndex += 1
                continue
            }

            guard currentHeader != nil else { continue }
            currentLines.append(
                SessionTranscriptDiffLinePresentation(
                    id: "\(fileIndex)-\(path)-h\(hunkIndex)-l\(currentLineIndex)",
                    kind: classifyDiffLine(line),
                    text: line
                )
            )
            currentLineIndex += 1
        }

        appendCurrentHunkIfNeeded()

        if hunks.isEmpty {
            let fallbackLines = lines.enumerated().map { index, line in
                SessionTranscriptDiffLinePresentation(
                    id: "\(fileIndex)-\(path)-fallback-\(index)",
                    kind: classifyDiffLine(line),
                    text: line
                )
            }
            return [
                SessionTranscriptDiffHunkPresentation(
                    id: "\(fileIndex)-\(path)-fallback",
                    header: "Diff",
                    lines: fallbackLines
                )
            ]
        }

        return hunks
    }

    private static func classifyDiffLine(_ line: String) -> SessionTranscriptDiffLinePresentation.Kind {
        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return .added
        }
        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return .removed
        }
        if line.hasPrefix(" ") {
            return .context
        }
        return .meta
    }

    private static func parseDiffPath(fromHeader header: String) -> String? {
        let prefix = "diff --git a/"
        guard header.hasPrefix(prefix) else { return nil }
        let tail = String(header.dropFirst(prefix.count))
        guard let separator = tail.range(of: " b/") else { return nil }
        let left = String(tail[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(tail[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if left != "dev/null", !left.isEmpty {
            return left
        }
        return right.isEmpty ? nil : right
    }

    private static func inferChangeKind(
        from change: [String: Any],
        movePath: String?
    ) -> SessionTranscriptFileChangeKind {
        if movePath != nil {
            return .moved
        }
        if change["add"] != nil {
            return .added
        }
        if change["delete"] != nil {
            return .deleted
        }
        if change["modify"] != nil || change["type"] != nil {
            let type = normalizeString(change["type"])?.lowercased()
            switch type {
            case "add", "create", "added":
                return .added
            case "delete", "remove", "deleted":
                return .deleted
            case "move", "rename", "moved":
                return .moved
            case "update", "modify", "modified":
                return .modified
            default:
                return .modified
            }
        }
        return .unknown
    }

    private static func inferLatestChangeKind(
        _ kindObject: [String: Any]?,
        movePath: String?
    ) -> SessionTranscriptFileChangeKind {
        if movePath != nil {
            return .moved
        }
        let type = normalizeString(kindObject?["type"])?.lowercased()
        switch type {
        case "add":
            return .added
        case "delete":
            return .deleted
        case "update":
            return .modified
        default:
            return .unknown
        }
    }

    private static func makeChangeSummary(
        kind: SessionTranscriptFileChangeKind,
        oldText: String?,
        newText: String?,
        diffFiles: [SessionTranscriptDiffFilePresentation]
    ) -> String? {
        if !diffFiles.isEmpty {
            return nil
        }

        let oldLineCount = oldText?.components(separatedBy: .newlines).count ?? 0
        let newLineCount = newText?.components(separatedBy: .newlines).count ?? 0

        switch kind {
        case .added:
            return newLineCount > 0 ? "\(newLineCount) lines created" : "Created file contents"
        case .deleted:
            return oldLineCount > 0 ? "\(oldLineCount) lines removed" : "Deleted file contents"
        case .modified:
            if oldLineCount > 0 || newLineCount > 0 {
                return "\(oldLineCount) → \(newLineCount) lines"
            }
            return "Updated file contents"
        case .moved:
            return "Moved file path"
        case .unknown:
            return nil
        }
    }

    private static func fallbackDiffPath(for entry: SessionTranscriptEntry) -> String? {
        let normalizedTitle = (entry.title ?? "").lowercased()
        if normalizedTitle.contains("diff") {
            return entry.toolName.map(fileName(from:)) ?? "diff"
        }
        return nil
    }

    private static func parseJSONObject(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func normalizeString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = normalizeString(value)?.lowercased() {
            switch string {
            case "true", "success", "succeeded", "completed", "complete", "ok":
                return true
            case "false", "failed", "error":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func normalizeInt(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = normalizeString(value) {
            return Int(string)
        }
        return nil
    }

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let normalized = normalizeString(value) {
                return normalized
            }
        }
        return nil
    }

    private static func normalizeMarkdownLinks(in raw: String) -> String {
        guard raw.contains("](/") else { return raw }
        let pattern = #"\]\((/[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let nsRange = NSRange(raw.startIndex..., in: raw)
        return regex.stringByReplacingMatches(
            in: raw,
            options: [],
            range: nsRange,
            withTemplate: "](file://$1)"
        )
    }

    private static func normalizeAppMentions(in raw: String) -> String {
        let pattern = #"\[(\$[^\]]+)\]\((?:app://[^)]+|file://[^)]+|/[^)]+SKILL\.md)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        guard !matches.isEmpty else { return raw }

        var result = raw
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let labelRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            result.replaceSubrange(fullRange, with: "`\(result[labelRange])`")
        }
        return result
    }

    static func fileName(from path: String) -> String {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return path }
        return URL(fileURLWithPath: normalized).lastPathComponent
    }

    private static func commandSummary(from rawBody: String) -> String? {
        guard let object = parseJSONObject(from: rawBody) else { return nil }
        let commandActions = (object["commandActions"] as? [[String: Any]]) ??
            (object["parsed_cmd"] as? [[String: Any]]) ??
            (object["parsedCmd"] as? [[String: Any]])
        guard let commandActions, !commandActions.isEmpty else { return nil }

        var exploreCount = 0
        var searchCount = 0
        var readCount = 0
        var editCount = 0
        var commandCount = 0

        for action in commandActions {
            let type = normalizeString(action["type"])?.lowercased() ?? ""
            switch type {
            case "listfiles", "listfile", "ls":
                exploreCount += 1
            case "search", "grep", "ripgrep", "rg":
                searchCount += 1
            case "read", "readfile":
                readCount += 1
            case "write", "writefile", "edit", "applypatch":
                editCount += 1
            default:
                commandCount += 1
            }
        }

        var parts: [String] = []
        if exploreCount > 0 {
            parts.append("Listed \(exploreCount) \(exploreCount == 1 ? "path" : "paths")")
        }
        if readCount > 0 {
            parts.append("Read \(readCount) \(readCount == 1 ? "file" : "files")")
        }
        if searchCount > 0 {
            parts.append("\(searchCount) \(searchCount == 1 ? "search" : "searches")")
        }
        if editCount > 0 {
            parts.append("Edited \(editCount) \(editCount == 1 ? "file" : "files")")
        }
        if commandCount > 0 || parts.isEmpty {
            parts.append("Ran \(commandActions.count) \(commandActions.count == 1 ? "command" : "commands")")
        }

        return parts.joined(separator: ", ")
    }

    private static func formattedGenericToolBody(
        _ object: [String: Any],
        excludingKeys: Set<String>
    ) -> String? {
        let filtered = object.filter { key, _ in
            !excludingKeys.contains(key)
        }
        guard !filtered.isEmpty else { return nil }
        return SessionTranscriptPresentationBuilder.stringify(filtered)
    }

    private static func genericToolCompactSummary(
        kind: SessionTranscriptGenericToolPresentation.Kind,
        object: [String: Any]
    ) -> String? {
        switch kind {
        case .plan:
            guard let items = parsePlanItems(from: object["plan"]), !items.isEmpty else { return nil }
            return items.count == 1 ? "1 step" : "\(items.count) steps"
        case .spawnAgent:
            return firstString(
                object["nickname"],
                object["agentNickname"],
                object["agent_id"],
                object["id"],
                object["agent_type"]
            )
        case .wait:
            if let count = genericToolListCount(
                object["ids"],
                object["agent_ids"]
            ) {
                return count == 1 ? "1 agent" : "\(count) agents"
            }
            return completedSummary(from: object["completed"]) ??
                humanizedStatus(normalizeString(object["status"]))
        case .stdin:
            return firstString(
                object["nickname"],
                object["agentNickname"],
                object["agent_id"],
                object["id"],
                object["session_id"]
            )
        case .toolResult, .toolCall:
            return firstString(
                humanizedStatus(normalizeString(object["status"])),
                object["nickname"],
                object["agent_id"],
                object["id"]
            )
        }
    }

    private static func genericToolSubtitle(
        kind: SessionTranscriptGenericToolPresentation.Kind,
        object: [String: Any]
    ) -> String? {
        switch kind {
        case .plan:
            return firstString(
                object["explanation"],
                object["message"],
                object["prompt"],
                object["description"]
            )
        case .spawnAgent:
            return firstString(
                object["message"],
                object["prompt"],
                object["description"]
            )
        case .wait:
            return firstString(
                completedMessage(from: object["completed"]),
                object["message"],
                object["prompt"],
                object["description"]
            )
        case .stdin:
            return truncatedText(
                normalizeString(object["chars"]) ?? normalizeString(object["text"]),
                limit: 96
            )
        case .toolResult, .toolCall:
            return firstString(
                object["message"],
                object["prompt"],
                object["description"],
                completedMessage(from: object["completed"])
            )
        }
    }

    private static func genericToolBadge(
        kind: SessionTranscriptGenericToolPresentation.Kind,
        entryKind: SessionTranscriptEntryKind,
        object: [String: Any]
    ) -> (text: String, tone: SessionTranscriptGenericToolPresentation.BadgeTone)? {
        if normalizedBool(object["timed_out"]) == true {
            return ("Timed Out", .warning)
        }

        if let status = humanizedStatus(normalizeString(object["status"])) {
            let tone: SessionTranscriptGenericToolPresentation.BadgeTone
            let lowercased = status.lowercased()
            if lowercased.contains("complete") || lowercased.contains("success") || lowercased == "done" {
                tone = .success
            } else if lowercased.contains("fail") || lowercased.contains("error") || lowercased.contains("cancel") {
                tone = .warning
            } else {
                tone = .accent
            }
            return (status, tone)
        }

        switch kind {
        case .plan:
            if let items = parsePlanItems(from: object["plan"]), !items.isEmpty {
                if items.contains(where: { $0.status == .inProgress }) {
                    return ("In Progress", .accent)
                }
                if items.allSatisfy({ $0.status == .completed }) {
                    return ("Completed", .success)
                }
                return ("Planned", .neutral)
            }
            return entryKind == .toolResult ? ("Updated", .neutral) : ("Planning", .accent)
        case .spawnAgent:
            return entryKind == .toolResult ? ("Started", .success) : ("Requested", .accent)
        case .wait:
            if completedSummary(from: object["completed"]) != nil {
                return ("Completed", .success)
            }
            return entryKind == .toolResult ? ("Updated", .neutral) : ("Waiting", .accent)
        case .stdin:
            return entryKind == .toolResult ? ("Sent", .success) : ("Queued", .accent)
        case .toolResult:
            return ("Result", .neutral)
        case .toolCall:
            return nil
        }
    }

    private static func genericToolListCount(_ candidates: Any?...) -> Int? {
        for candidate in candidates {
            if let array = candidate as? [Any], !array.isEmpty {
                return array.count
            }
        }
        return nil
    }

    private static func parsePlanItems(
        from value: Any?
    ) -> [SessionTranscriptPlanStepPresentation]? {
        guard let array = value as? [[String: Any]] else { return nil }
        let items = array.enumerated().compactMap { index, item -> SessionTranscriptPlanStepPresentation? in
            guard let step = normalizeString(item["step"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !step.isEmpty else {
                return nil
            }
            let rawStatus = normalizeString(item["status"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? "pending"
            let status: SessionTranscriptPlanStepPresentation.Status
            switch rawStatus {
            case "completed", "complete", "done", "success":
                status = .completed
            case "in_progress", "inprogress", "running", "active":
                status = .inProgress
            default:
                status = .pending
            }
            return SessionTranscriptPlanStepPresentation(
                id: "plan-\(index)",
                step: step,
                status: status
            )
        }
        return items.isEmpty ? nil : items
    }

    private static func genericToolFieldValue(for key: String, value: Any?) -> String? {
        guard let value else { return nil }

        if key == "timed_out", normalizedBool(value) != true {
            return nil
        }

        if key == "timeout_ms", let milliseconds = normalizedInt(value) {
            return "\(milliseconds) ms"
        }

        if let object = value as? [String: Any] {
            return firstString(
                object["message"],
                humanizedStatus(normalizeString(object["status"])),
                object["nickname"],
                object["agent_id"],
                object["id"]
            )
        }

        if let array = value as? [Any], !array.isEmpty {
            let texts = array.compactMap(normalizeString)
            if !texts.isEmpty {
                return texts.count <= 3
                    ? texts.joined(separator: ", ")
                    : "\(texts.count) items"
            }
            return "\(array.count) items"
        }

        if let boolean = normalizedBool(value) {
            return boolean ? "Yes" : "No"
        }

        if key == "completed" {
            return completedSummary(from: value)
        }

        if key == "status" {
            return humanizedStatus(normalizeString(value))
        }

        return normalizeString(value)
    }

    private static func diffSummaryTitle(_ files: [SessionTranscriptDiffFilePresentation]) -> String {
        if files.count == 1, let first = files.first {
            return "Edited \(fileName(from: first.path))"
        }
        return "Edited \(files.count) files"
    }

    private static func diffSummarySubtitle(_ files: [SessionTranscriptDiffFilePresentation]) -> String? {
        guard !files.isEmpty else { return nil }
        let totalHunks = files.reduce(0) { $0 + $1.hunkCount }
        if files.count == 1, let first = files.first {
            if totalHunks > 0 {
                return "\(totalHunks) \(totalHunks == 1 ? "hunk" : "hunks")"
            }
            return first.path
        }
        guard totalHunks > 0 else { return nil }
        return "\(totalHunks) \(totalHunks == 1 ? "hunk" : "hunks")"
    }

    private static func completedSummary(from value: Any?) -> String? {
        if let bool = normalizedBool(value) {
            return bool ? "Completed" : nil
        }
        if let object = value as? [String: Any] {
            return firstString(
                humanizedStatus(normalizeString(object["status"])),
                object["message"],
                object["nickname"],
                object["agent_id"],
                object["id"]
            )
        }
        if let text = normalizeString(value) {
            return humanizedStatus(text) ?? text
        }
        return nil
    }

    private static func completedMessage(from value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        return firstString(
            object["message"],
            object["content"],
            object["summary"]
        )
    }

    private static func humanizedStatus(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return humanizedFieldName(trimmed)
    }

    private static func truncatedText(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private static func normalizedBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func normalizedInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String,
           let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return nil
    }

    private static func humanizedFieldName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct SessionTranscriptMarkdownView: View {
    let markdown: String
    let role: SessionTranscriptEntryRole
    let kind: SessionTranscriptEntryKind
    let onOpenFilePath: (String) -> Void

    private var blocks: [SessionMarkdownBlock] {
        SessionTranscriptRichContentParser.markdownBlocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(AppPalette.accent)
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL {
                let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    onOpenFilePath(path)
                    return .handled
                }
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func blockView(_ block: SessionMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level: level))
                .foregroundStyle(AppPalette.primaryText)
        case .paragraph(let text):
            inlineText(text)
                .font(kind == .thinking ? .callout : .body)
                .foregroundStyle(kind == .thinking ? AppPalette.secondaryText : AppPalette.primaryText)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.callout)
                    .foregroundStyle(AppPalette.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.chatToolBackground.opacity(0.8))
            )
        case .code(let language, let code):
            SessionTranscriptMonospaceBlock(
                text: code,
                language: language,
                accentColor: role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent
            )
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.marker)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(width: 22 + CGFloat(item.depth * 14), alignment: .leading)
                        inlineText(item.text)
                            .font(.callout)
                            .foregroundStyle(AppPalette.primaryText)
                    }
                }
            }
        case .image(let altText, let source):
            SessionTranscriptInlineImageView(
                source: source,
                altText: altText.isEmpty ? "Image" : altText
            )
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attributed = SessionTranscriptRichContentParser.attributedInlineMarkdown(raw) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.bold)
        case 2:
            return .title3.weight(.semibold)
        case 3:
            return .headline.weight(.semibold)
        default:
            return .subheadline.weight(.semibold)
        }
    }
}

struct SessionTranscriptToolRichContentView: View {
    let entry: SessionTranscriptEntry

    private var richContent: SessionTranscriptRichToolContent? {
        SessionTranscriptRichContentParser.richToolContent(for: entry)
    }

    var body: some View {
        if let richContent {
            switch richContent {
            case .commandExecution(let command):
                commandExecutionCard(command)
            case .fileChanges(let changes):
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(changes) { change in
                        fileChangeCard(change)
                    }
                }
            case .diff(let files):
                diffFileList(files, compact: false)
            case .toolDetails(let tool):
                genericToolCard(tool)
            }
        } else {
            SessionTranscriptMonospaceBlock(
                text: entry.body,
                language: nil,
                accentColor: AppPalette.terminalLineTool
            )
        }
    }

    @ViewBuilder
    private func genericToolCard(
        _ tool: SessionTranscriptGenericToolPresentation
    ) -> some View {
        let badgeTint = genericToolBadgeTint(tool.badgeTone)
        SessionSurfaceCard(
            cornerRadius: 14,
            fillColor: AppPalette.chatToolBackground.opacity(0.95),
            strokeColor: badgeTint.opacity(tool.badgeText == nil ? 0.18 : 0.24)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: genericToolSymbolName(tool.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeTint)
                    Text(tool.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                    if let badgeText = tool.badgeText, !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(badgeTint.opacity(0.12))
                            )
                    }
                    Spacer(minLength: 0)
                }

                if let compactSummary = tool.compactSummary, !compactSummary.isEmpty {
                    Text(compactSummary)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                        .textSelection(.enabled)
                }

                if let subtitle = tool.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if !tool.planItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tool.planItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.status.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(planStatusTint(item.status))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.step)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(AppPalette.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.status.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(planStatusTint(item.status))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(planStatusTint(item.status).opacity(0.12))
                                        )
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if !tool.fields.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tool.fields) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .frame(width: 88, alignment: .leading)
                                Text(field.value)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppPalette.primaryText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let body = tool.body, !body.isEmpty {
                    SessionTranscriptMonospaceBlock(
                        text: body,
                        language: nil,
                        accentColor: badgeTint
                    )
                }
            }
            .padding(12)
        }
    }

    private func genericToolSymbolName(
        _ kind: SessionTranscriptGenericToolPresentation.Kind
    ) -> String {
        switch kind {
        case .plan:
            return "checklist"
        case .spawnAgent:
            return "person.badge.plus"
        case .wait:
            return "hourglass"
        case .stdin:
            return "arrow.up.to.line.compact"
        case .toolResult:
            return "checkmark.circle"
        case .toolCall:
            return "hammer"
        }
    }

    private func genericToolBadgeTint(
        _ tone: SessionTranscriptGenericToolPresentation.BadgeTone
    ) -> Color {
        switch tone {
        case .accent:
            return AppPalette.accent
        case .success:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return AppPalette.secondaryText
        }
    }

    private func planStatusTint(
        _ status: SessionTranscriptPlanStepPresentation.Status
    ) -> Color {
        switch status {
        case .pending:
            return AppPalette.secondaryText
        case .inProgress:
            return AppPalette.accent
        case .completed:
            return .green
        }
    }

    @ViewBuilder
    private func commandExecutionCard(
        _ command: SessionTranscriptCommandRunPresentation
    ) -> some View {
        SessionSurfaceCard(
            cornerRadius: 14,
            fillColor: AppPalette.chatToolBackground.opacity(0.96),
            strokeColor: commandStatusTint(command.status).opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(commandStatusTint(command.status))
                    Text("Ran command")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                    statusBadge(for: command)
                    Spacer(minLength: 0)
                    Text(command.command)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPalette.secondaryText)
                        .lineLimit(1)
                    if let exitCode = command.exitCode {
                        Text("Exit code \(exitCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    if let durationText = command.durationText {
                        Text(durationText)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }
                SessionTranscriptMonospaceBlock(
                    text: "$ " + command.command,
                    language: "shell",
                    accentColor: commandStatusTint(command.status)
                )

                if let cwd = command.cwd {
                    LabeledContent {
                        Text(cwd)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    } label: {
                        Text("Shell")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }

                if let summary = command.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                } else if command.logs?.isEmpty != false {
                    Text(command.waitingDescription)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if let logs = command.logs, !logs.isEmpty {
                    ScrollView(.vertical) {
                        SessionTranscriptMonospaceBlock(
                            text: logs,
                            language: nil,
                            accentColor: commandStatusTint(command.status)
                        )
                    }
                    .frame(maxHeight: 240)
                }

                if !command.supplementalEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(command.supplementalEntries) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .foregroundStyle(AppPalette.secondaryText)
                                if item.kind == .toolResult {
                                    ScrollView(.vertical) {
                                        SessionTranscriptMonospaceBlock(
                                            text: item.body,
                                            language: nil,
                                            accentColor: commandStatusTint(command.status)
                                        )
                                    }
                                    .frame(maxHeight: 220)
                                } else {
                                    SessionTranscriptMonospaceBlock(
                                        text: item.body,
                                        language: nil,
                                        accentColor: AppPalette.accent
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func fileChangeCard(_ change: SessionTranscriptFileChangePresentation) -> some View {
        SessionSurfaceCard(
            cornerRadius: 12,
            fillColor: AppPalette.chatToolBackground.opacity(0.95),
            strokeColor: change.kind.tint.opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: change.kind.iconSystemName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(change.kind.tint)
                    Text(SessionTranscriptRichContentParser.fileName(from: change.path))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(change.kind.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(change.kind.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(change.kind.tint.opacity(0.14))
                        )
                }

                Text(change.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
                    .textSelection(.enabled)

                if let movePath = change.movePath, !movePath.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(movePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .textSelection(.enabled)
                    }
                }

                if let summary = change.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }

                if !change.diffFiles.isEmpty {
                    diffFileList(change.diffFiles, compact: true)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func statusBadge(
        for command: SessionTranscriptCommandRunPresentation
    ) -> some View {
        HStack(spacing: 6) {
            statusDot(for: command.status)
            Text(command.status.badgeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(commandStatusTint(command.status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(commandStatusTint(command.status).opacity(0.12))
        )
    }

    private func commandStatusTint(
        _ status: SessionTranscriptCommandRunPresentation.Status
    ) -> Color {
        switch status.tone {
        case .running:
            return AppPalette.accent
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    @ViewBuilder
    private func statusDot(
        for status: SessionTranscriptCommandRunPresentation.Status
    ) -> some View {
        switch status.tone {
        case .running:
            LivePulseDot(size: 8)
        case .success, .failure:
            Circle()
                .fill(commandStatusTint(status))
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private func diffFileList(_ files: [SessionTranscriptDiffFilePresentation], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if !compact || index < 3 {
                    SessionSurfaceCard(
                        cornerRadius: 10,
                        fillColor: Color.clear,
                        strokeColor: AppPalette.chromeSurfaceStroke
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(file.path)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(AppPalette.primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(file.hunkCount == 1 ? "1 hunk" : "\(file.hunkCount) hunks")
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.secondaryText)
                            }

                            if compact {
                                Text(file.preview)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .lineLimit(3)
                            }

                            transcriptDiffHunks(file.hunks, compact: compact)
                        }
                        .padding(10)
                    }
                }
            }

            if compact && files.count > 3 {
                Text("+ \(files.count - 3) more files")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func transcriptDiffHunks(
        _ hunks: [SessionTranscriptDiffHunkPresentation],
        compact: Bool
    ) -> some View {
        let visibleHunks = compact ? Array(hunks.prefix(1)) : hunks

        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleHunks) { hunk in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunk.lines.enumerated()), id: \.element.id) { index, line in
                        if !compact || index < 12 {
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(diffForeground(for: line.kind))
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(diffBackground(for: line.kind))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if compact,
               let first = visibleHunks.first,
               first.lines.count > 12 {
                Text("+ \(first.lines.count - 12) more lines")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }

    private func diffForeground(for kind: SessionTranscriptDiffLinePresentation.Kind) -> Color {
        switch kind {
        case .added:
            return .green
        case .removed:
            return .red
        case .context, .meta:
            return AppPalette.primaryText
        }
    }

    private func diffBackground(for kind: SessionTranscriptDiffLinePresentation.Kind) -> Color {
        switch kind {
        case .added:
            return .green.opacity(0.14)
        case .removed:
            return .red.opacity(0.14)
        case .context:
            return Color.clear
        case .meta:
            return AppPalette.chromeSurface.opacity(0.75)
        }
    }
}

struct SessionTranscriptMonospaceBlock: View {
    let text: String
    let language: String?
    let accentColor: Color

    var body: some View {
        SessionSurfaceCard(
            cornerRadius: 12,
            fillColor: AppPalette.chromeSurface.opacity(0.9),
            strokeColor: AppPalette.chromeSurfaceStroke
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text.isEmpty ? " " : text)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppPalette.primaryText)
                        .lineSpacing(1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
    }
}
