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
    func parseRejectsNonTerminalURL() {
        #expect(TerminalAuthURLParser.parse("https://example.com") == nil)
        #expect(TerminalAuthURLParser.parse("unhappy://account?abc123") == nil)
    }

    @Test
    func parseTrimsWhitespace() {
        let request = TerminalAuthURLParser.parse("   unhappy://terminal?abc123   ")
        #expect(request?.publicKey == "abc123")
    }
}
