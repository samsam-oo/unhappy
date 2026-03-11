import Foundation
import CoreKit
import SessionKit

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

func sessionsMakeOptimisticUserPayload(text: String, imageDataURLs: [String] = []) -> String {
    let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedImageDataURLs = imageDataURLs
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let payload: [String: Any]
    if normalizedImageDataURLs.isEmpty {
        payload = [
            "role": "user",
            "content": [
                "type": "text",
                "text": normalizedText,
            ],
        ]
    } else {
        var content: [[String: Any]] = []
        if !normalizedText.isEmpty {
            content.append([
                "type": "text",
                "text": normalizedText,
            ])
        }
        content.append(
            contentsOf: normalizedImageDataURLs.map { imageURL in
                [
                    "type": "input_image",
                    "image_url": imageURL,
                ]
            }
        )
        payload = [
            "role": "user",
            "content": content,
        ]
    }

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let encodedPayload = String(data: data, encoding: .utf8) else {
        return text
    }
    return encodedPayload
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

func sessionsMultiAgentInProgressCount(_ rows: [APISession]) -> Int {
    rows.reduce(0) { partialResult, session in
        partialResult + SessionRuntimeContext(session: session).collabInProgressCount
    }
}
