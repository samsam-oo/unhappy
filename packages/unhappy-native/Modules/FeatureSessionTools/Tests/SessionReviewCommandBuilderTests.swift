import Testing
@testable import FeatureSessionTools

struct SessionReviewCommandBuilderTests {
    @Test
    func verifyRepositoryScriptUsesSentinels() {
        let command = SessionReviewCommandBuilder.verifyRepositoryScript(repoPath: "/tmp/repo")

        #expect(command.contains("git -C '/tmp/repo' rev-parse --is-inside-work-tree"))
        #expect(command.contains(SessionReviewCommandBuilder.repoOKSentinel))
        #expect(command.contains(SessionReviewCommandBuilder.noRepoSentinel))
    }

    @Test
    func diffCommandUsesHeadWhenAvailable() {
        let withHead = SessionReviewCommandBuilder.diffCommand(repoPath: "/tmp/repo", hasHead: true)
        let withoutHead = SessionReviewCommandBuilder.diffCommand(repoPath: "/tmp/repo", hasHead: false)

        #expect(withHead.contains("diff --no-ext-diff HEAD"))
        #expect(withoutHead.contains("diff --no-ext-diff --cached"))
    }

    @Test
    func commandsQuoteSingleQuotesInPaths() {
        let command = SessionReviewCommandBuilder.verifyHeadScript(repoPath: "/tmp/repo'space")
        #expect(command.contains("'\"'\"'"))
    }
}
