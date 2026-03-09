import Foundation

public enum AccountSecretCodec {
    public static func decode(_ raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = Base64URLCodec.decode(trimmed), data.count == 32 {
            return data
        }
        if let data = decodeBase32Secret(trimmed), data.count == 32 {
            return data
        }
        return nil
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let base32Map: [Character: UInt8] = {
        Dictionary(uniqueKeysWithValues: base32Alphabet.enumerated().map { ($0.element, UInt8($0.offset)) })
    }()

    private static func decodeBase32Secret(_ raw: String) -> Data? {
        let normalized = raw.uppercased()
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
            .replacingOccurrences(of: "8", with: "B")
            .replacingOccurrences(of: "9", with: "G")
        let cleaned = normalized.filter { base32Map[$0] != nil }
        guard !cleaned.isEmpty else { return nil }

        var buffer: UInt32 = 0
        var bufferLength: Int = 0
        var bytes: [UInt8] = []

        for character in cleaned {
            guard let value = base32Map[character] else {
                return nil
            }
            buffer = (buffer << 5) | UInt32(value)
            bufferLength += 5

            while bufferLength >= 8 {
                bufferLength -= 8
                let byte = UInt8((buffer >> UInt32(bufferLength)) & 0xFF)
                bytes.append(byte)
            }
        }
        return Data(bytes)
    }
}
