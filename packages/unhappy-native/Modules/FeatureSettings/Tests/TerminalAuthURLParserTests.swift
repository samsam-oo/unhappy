import Testing
@testable import FeatureSettings

struct TerminalAuthURLParserTests {
    @Test
    func parseRawQueryTerminalURL() {
        let request = TerminalAuthURLParser.parse("unhappy://terminal?abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseKeyQueryItemTerminalURL() {
        let request = TerminalAuthURLParser.parse("unhappy://terminal?key=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parsePublicKeyQueryItemTerminalURL() {
        let request = TerminalAuthURLParser.parse("unhappy://terminal?publicKey=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parsePathNormalizedTerminalURL() {
        let request = TerminalAuthURLParser.parse("unhappy:/terminal?k=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseWebTerminalConnectURLWithHashKey() {
        let request = TerminalAuthURLParser.parse("https://app.unhappy.im/terminal/connect#key=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseWebTerminalConnectURLWithQueryKey() {
        let request = TerminalAuthURLParser.parse("https://app.unhappy.im/terminal/connect?key=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseWebTerminalConnectURLWithRawHashValue() {
        let request = TerminalAuthURLParser.parse("https://app.unhappy.im/terminal/connect#abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseRejectsNonTerminalURL() {
        #expect(TerminalAuthURLParser.parse("https://example.com") == nil)
        #expect(TerminalAuthURLParser.parse("unhappy://account?abc123") == nil)
        #expect(TerminalAuthURLParser.parse("https://app.unhappy.im/account/connect#key=abc123") == nil)
    }

    @Test
    func parseTrimsWhitespace() {
        let request = TerminalAuthURLParser.parse("   unhappy://terminal?abc123   ")
        #expect(request?.publicKey == "abc123")
    }
}
