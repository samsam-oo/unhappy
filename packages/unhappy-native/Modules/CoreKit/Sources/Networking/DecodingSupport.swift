import Foundation

enum DecodingSupport {
    static func normalizeUnixTimestamp(_ raw: TimeInterval) -> TimeInterval {
        let absRaw = abs(raw)
        if absRaw >= 10_000_000_000_000 {
            // Microseconds -> seconds
            return raw / 1_000_000
        }
        if absRaw >= 10_000_000_000 {
            // Milliseconds -> seconds
            return raw / 1_000
        }
        return raw
    }

    static func normalizeDisplayText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return repairedMojibakeText(from: trimmed) ?? trimmed
    }

    private static func repairedMojibakeText(from text: String) -> String? {
        guard let latin1 = text.data(using: .isoLatin1),
              let repaired = String(data: latin1, encoding: .utf8),
              repaired != text else {
            return nil
        }

        if shouldPreferRepairedText(original: text, repaired: repaired) {
            return repaired
        }
        return nil
    }

    private static func shouldPreferRepairedText(original: String, repaired: String) -> Bool {
        if containsHangulOrCJK(repaired) && !containsHangulOrCJK(original) {
            return true
        }

        if containsEmoji(repaired) && original.contains("ðŸ") {
            return true
        }

        if original.contains("Ã") || original.contains("Â") || original.contains("â") || original.contains("ðŸ") {
            return true
        }

        return false
    }

    private static func containsHangulOrCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF, // Hangul Jamo
                0x3130...0x318F, // Hangul Compatibility Jamo
                0xAC00...0xD7AF, // Hangul Syllables
                0x4E00...0x9FFF, // CJK Unified Ideographs
                0x3400...0x4DBF: // CJK Extension A
                return true
            default:
                return false
            }
        }
    }

    private static func containsEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                return value
            }
            if let value = Double(trimmed) {
                return Int(value)
            }
        }
        return nil
    }

    func decodeFlexibleTimeIntervalIfPresent(forKey key: Key) -> TimeInterval? {
        if let value = try? decodeIfPresent(TimeInterval.self, forKey: key) {
            return DecodingSupport.normalizeUnixTimestamp(value)
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return DecodingSupport.normalizeUnixTimestamp(TimeInterval(value))
        }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(trimmed) {
                return DecodingSupport.normalizeUnixTimestamp(value)
            }
        }
        return nil
    }

    func decodeFlexibleTimestampStringIfPresent(forKey key: Key) -> String? {
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = decodeFlexibleTimeIntervalIfPresent(forKey: key) {
            guard value > 0 else { return nil }
            return Date(timeIntervalSince1970: value).ISO8601Format()
        }
        return nil
    }
}
