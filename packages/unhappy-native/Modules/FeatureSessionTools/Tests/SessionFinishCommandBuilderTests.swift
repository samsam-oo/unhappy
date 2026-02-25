import Testing
@testable import FeatureSessionTools

struct SessionFinishCommandBuilderTests {
    @Test
    func commitCommandQuotesMessageAndPath() {
        let command = SessionFinishCommandBuilder.commitCommand(
            worktreePath: "/tmp/repo's",
            message: "feat: it's done"
        )

        #expect(command.contains("git -C '/tmp/repo'\"'\"'s' commit -m 'feat: it'\"'\"'s done'"))
    }

    @Test
    func mergeCommandTargetsBasePathAndBranch() {
        let command = SessionFinishCommandBuilder.mergeCommand(
            basePath: "/tmp/base",
            branch: "feature/test"
        )

        #expect(command == "git -C '/tmp/base' merge 'feature/test' --no-edit")
    }

    @Test
    func createPRCommandUsesCdWithBasePath() {
        let command = SessionFinishCommandBuilder.createPRCommand(
            basePath: "/tmp/base",
            mainBranch: "main",
            branch: "feature"
        )

        #expect(command.contains("cd '/tmp/base' && gh pr create"))
        #expect(command.contains("--base 'main'"))
        #expect(command.contains("--head 'feature'"))
    }
}
