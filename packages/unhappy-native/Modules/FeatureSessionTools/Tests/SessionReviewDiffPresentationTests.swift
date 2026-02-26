import Testing
@testable import FeatureSessionTools

struct SessionReviewDiffPresentationTests {
    @Test
    func parseFilesBuildsFileSummaries() {
        let diff = """
        diff --git a/Sources/A.swift b/Sources/A.swift
        index 111..222 100644
        --- a/Sources/A.swift
        +++ b/Sources/A.swift
        @@ -1,2 +1,2 @@
        -old
        +new
        diff --git a/Tests/BTests.swift b/Tests/BTests.swift
        index 333..444 100644
        --- a/Tests/BTests.swift
        +++ b/Tests/BTests.swift
        @@ -3,0 +4,2 @@
        +added1
        +added2
        """

        let files = SessionReviewDiffPresentationBuilder.parseFiles(from: diff)

        #expect(files.count == 2)
        #expect(files[0].path == "Sources/A.swift")
        #expect(files[0].hunkCount == 1)
        #expect(files[0].preview.contains("-old"))
        #expect(files[1].path == "Tests/BTests.swift")
        #expect(files[1].hunkCount == 1)
        #expect(files[1].preview.contains("+added1"))
    }

    @Test
    func parseFilesReturnsEmptyForNoDiff() {
        let files = SessionReviewDiffPresentationBuilder.parseFiles(from: "")
        #expect(files.isEmpty)
    }

    @Test
    func parsePathUsesRightSideWhenLeftIsDevNull() {
        let path = SessionReviewDiffPresentationBuilder.parsePath(
            fromHeader: "diff --git a/dev/null b/Sources/NewFile.swift"
        )
        #expect(path == "Sources/NewFile.swift")
    }
}
