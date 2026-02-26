import Testing
@testable import FeatureSessionTools

struct SessionWorktreeInfoTests {
    @Test
    func extractParsesPOSIXWorktreePath() {
        let value = SessionWorktreeInfo.extract(from: "/Users/me/project/.unhappy/worktree/feature-a")

        #expect(value?.basePath == "/Users/me/project")
        #expect(value?.worktreeName == "feature-a")
        #expect(value?.worktreePath == "/Users/me/project/.unhappy/worktree/feature-a")
    }

    @Test
    func extractParsesWindowsWorktreePath() {
        let value = SessionWorktreeInfo.extract(from: "C:\\repo\\.unhappy\\worktree\\feature-a")

        #expect(value?.basePath == "C:\\repo")
        #expect(value?.worktreeName == "feature-a")
    }

    @Test
    func extractReturnsNilForNonWorktreePath() {
        let value = SessionWorktreeInfo.extract(from: "/Users/me/project")
        #expect(value == nil)
    }
}
