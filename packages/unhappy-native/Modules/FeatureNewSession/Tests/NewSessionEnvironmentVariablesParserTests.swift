import Testing
@testable import FeatureNewSession

struct NewSessionEnvironmentVariablesParserTests {
    @Test
    func parseReturnsDictionary() throws {
        let parsed = try NewSessionEnvironmentVariablesParser.parse(
            """
            # comment
            OPENAI_API_KEY=test-key
            ANTHROPIC_BASE_URL=https://example.com
            """
        )

        #expect(parsed["OPENAI_API_KEY"] == "test-key")
        #expect(parsed["ANTHROPIC_BASE_URL"] == "https://example.com")
    }

    @Test
    func parseThrowsWhenLineIsInvalid() {
        #expect(throws: NewSessionError.invalidEnvironmentVariable(line: 1, value: "INVALID")) {
            _ = try NewSessionEnvironmentVariablesParser.parse("INVALID")
        }
    }
}
