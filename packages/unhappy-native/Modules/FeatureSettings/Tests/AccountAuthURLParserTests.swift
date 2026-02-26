import Foundation
import Testing
@testable import FeatureSettings

struct AccountAuthURLParserTests {
    @Test
    func parseSupportsRawQueryFormat() {
        let request = AccountAuthURLParser.parse("unhappy://account?abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseSupportsQueryParameterFormat() {
        let request = AccountAuthURLParser.parse("unhappy://account?publicKey=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseSupportsPathNormalizedFormat() {
        let request = AccountAuthURLParser.parse("unhappy:/account?key=abc123")
        #expect(request?.publicKey == "abc123")
    }

    @Test
    func parseReturnsNilForInvalidSchemeOrHost() {
        #expect(AccountAuthURLParser.parse("https://example.com") == nil)
        #expect(AccountAuthURLParser.parse("unhappy://terminal?abc123") == nil)
    }
}
