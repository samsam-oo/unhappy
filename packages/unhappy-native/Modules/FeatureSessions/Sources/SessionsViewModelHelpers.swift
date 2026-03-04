import Foundation
import CoreKit

func sessionsMergeFetchedMessages(
    fetchedMessages: [APISessionMessage],
    cachedMessages: [APISessionMessage]?
) -> [APISessionMessage] {
    guard let cachedMessages, !cachedMessages.isEmpty else {
        return fetchedMessages
    }
    guard fetchedMessages.count >= cachedMessages.count else {
        return fetchedMessages
    }

    for index in cachedMessages.indices where cachedMessages[index] != fetchedMessages[index] {
        return fetchedMessages
    }

    if fetchedMessages.count == cachedMessages.count {
        return cachedMessages
    }
    return cachedMessages + Array(fetchedMessages.dropFirst(cachedMessages.count))
}

func sessionsNormalizeMessageOrder(_ messages: [APISessionMessage]) -> [APISessionMessage] {
    messages.sorted { lhs, rhs in
        if lhs.seq != rhs.seq {
            return lhs.seq < rhs.seq
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.id < rhs.id
    }
}

func sessionsMakeOptimisticUserPayload(text: String) -> String {
    let payload: [String: Any] = [
        "role": "user",
        "content": [
            "type": "text",
            "text": text,
        ],
    ]
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let encodedPayload = String(data: data, encoding: .utf8) else {
        return text
    }
    return encodedPayload
}

func sessionsArrayValue(from value: Any?) -> [Any] {
    guard let value else { return [] }
    if let array = value as? [Any] {
        return array
    }
    return []
}

func sessionsNormalizeQueuedComposerMessageTexts(_ values: [Any]) -> [String] {
    var normalized: [String] = []
    normalized.reserveCapacity(values.count)

    for value in values {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            normalized.append(trimmed)
            continue
        }
        if let payload = value as? [String: Any] {
            let textCandidates: [Any?] = [payload["text"], payload["message"], payload["value"]]
            for candidate in textCandidates {
                guard let raw = candidate as? String else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                normalized.append(trimmed)
                break
            }
        }
    }

    var deduped: [String] = []
    deduped.reserveCapacity(normalized.count)
    for message in normalized where !deduped.contains(message) {
        deduped.append(message)
    }
    return deduped
}

func sessionsNormalizedNonNegativeInt(from value: Any?) -> Int? {
    if let intValue = value as? Int {
        return max(0, intValue)
    }
    if let number = value as? NSNumber {
        return max(0, number.intValue)
    }
    if let string = value as? String, let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return max(0, parsed)
    }
    return nil
}

func sessionsMergeLatestRows(_ latestRows: [APISession], into existingRows: [APISession]) -> [APISession] {
    var byID: [String: APISession] = [:]
    byID.reserveCapacity(existingRows.count + latestRows.count)

    for row in existingRows {
        byID[row.id] = row
    }
    for row in latestRows {
        byID[row.id] = row
    }

    return byID.values.sorted { lhs, rhs in
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.id > rhs.id
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
