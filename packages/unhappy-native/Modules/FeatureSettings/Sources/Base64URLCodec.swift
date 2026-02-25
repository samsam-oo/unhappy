import Foundation

enum Base64URLCodec {
    static func decode(_ raw: String) -> Data? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !normalized.isEmpty else { return nil }

        let remainder = normalized.count % 4
        let padded: String
        if remainder == 0 {
            padded = normalized
        } else {
            padded = normalized + String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: padded)
    }
}
