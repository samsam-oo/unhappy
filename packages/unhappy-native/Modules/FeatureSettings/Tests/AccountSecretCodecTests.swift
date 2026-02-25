import Foundation
import Testing
@testable import FeatureSettings

struct AccountSecretCodecTests {
    @Test
    func decodeAcceptsBase64URLSecret() {
        let secret = Data(repeating: 0x2A, count: 32)
        let encoded = Base64URLCodec.encode(secret)

        let decoded = AccountSecretCodec.decode(encoded)

        #expect(decoded == secret)
    }

    @Test
    func decodeAcceptsBase32Secret() {
        let secret = Data((0..<32).map(UInt8.init))
        let encoded = asBase32(secret)

        let decoded = AccountSecretCodec.decode(encoded)

        #expect(decoded == secret)
    }

    @Test
    func decodeNormalizesCommonBase32Typos() {
        let secret = firstSeedContainingTypoCandidates()
        let encoded = asBase32(secret)
        let mutated = mutateBase32ForTypoRecovery(encoded)

        let decoded = AccountSecretCodec.decode(mutated.value)

        #expect(mutated.changed)
        #expect(decoded == secret)
    }

    @Test
    func decodeRejectsNon32ByteValue() {
        let shortSecret = Data(repeating: 0x11, count: 16)

        #expect(AccountSecretCodec.decode(Base64URLCodec.encode(shortSecret)) == nil)
    }
}

private func asBase32(_ data: Data) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    var buffer: Int = 0
    var bufferLength = 0
    var output = ""

    for byte in data {
        buffer = (buffer << 8) | Int(byte)
        bufferLength += 8

        while bufferLength >= 5 {
            bufferLength -= 5
            let index = (buffer >> bufferLength) & 0x1F
            output.append(alphabet[index])
        }
    }

    if bufferLength > 0 {
        let index = (buffer << (5 - bufferLength)) & 0x1F
        output.append(alphabet[index])
    }

    return output
}

private func firstSeedContainingTypoCandidates() -> Data {
    for value in UInt8.min...UInt8.max {
        let candidate = Data(repeating: value, count: 32)
        let encoded = asBase32(candidate)
        if encoded.contains("O") || encoded.contains("I") || encoded.contains("B") || encoded.contains("G") {
            return candidate
        }
    }
    return Data((0..<32).map(UInt8.init))
}

private func mutateBase32ForTypoRecovery(_ source: String) -> (value: String, changed: Bool) {
    var output = source
    var changed = false

    for replacement in [(from: "O", to: "0"), (from: "I", to: "1"), (from: "B", to: "8"), (from: "G", to: "9")] {
        if let index = output.firstIndex(of: Character(replacement.from)) {
            output.replaceSubrange(index...index, with: replacement.to)
            changed = true
        }
    }
    return (output, changed)
}
