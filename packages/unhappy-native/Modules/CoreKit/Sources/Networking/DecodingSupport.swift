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
}
