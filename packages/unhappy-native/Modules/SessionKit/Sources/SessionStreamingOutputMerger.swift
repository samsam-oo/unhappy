import Foundation

public enum SessionStreamingOutputMerger {
    public static func merge(existing: String, chunk: String) -> String {
        guard !chunk.isEmpty else { return existing }
        guard !existing.isEmpty else { return chunk }

        if chunk.hasPrefix(existing) {
            return chunk
        }
        if existing.hasSuffix(chunk) {
            return existing
        }

        let overlap = suffixPrefixOverlapLength(existing: existing, incoming: chunk)
        if overlap > 0 {
            let remainder = String(chunk.dropFirst(overlap))
            guard !remainder.isEmpty else { return existing }
            if shouldInsertWordBoundary(existing: existing, incoming: remainder) {
                return existing + " " + remainder
            }
            return existing + remainder
        }

        if shouldInsertWordBoundary(existing: existing, incoming: chunk) {
            return existing + " " + chunk
        }
        return existing + chunk
    }

    private static func shouldInsertWordBoundary(existing: String, incoming: String) -> Bool {
        guard let existingLast = existing.last, let incomingFirst = incoming.first else {
            return false
        }
        if existingLast.isWhitespace || incomingFirst.isWhitespace {
            return false
        }
        return existingLast.isLetter || existingLast.isNumber
            ? (incomingFirst.isLetter || incomingFirst.isNumber)
            : false
    }

    private static func suffixPrefixOverlapLength(existing: String, incoming: String) -> Int {
        let maxOverlap = min(existing.count, incoming.count)
        guard maxOverlap > 0 else { return 0 }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if existing.suffix(overlap) == incoming.prefix(overlap) {
                return overlap
            }
        }
        return 0
    }
}
