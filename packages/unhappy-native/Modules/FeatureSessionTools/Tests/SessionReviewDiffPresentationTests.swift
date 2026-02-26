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
        #expect(files[0].hunks.count == 1)
        #expect(files[0].hunks[0].header == "@@ -1,2 +1,2 @@")
        #expect(files[1].path == "Tests/BTests.swift")
        #expect(files[1].hunkCount == 1)
        #expect(files[1].preview.contains("+added1"))
        #expect(files[1].hunks.count == 1)
    }

    @Test
    func parseFilesParsesMultipleHunksWithLineKinds() throws {
        let diff = [
            "diff --git a/Sources/A.swift b/Sources/A.swift",
            "index 111..222 100644",
            "--- a/Sources/A.swift",
            "+++ b/Sources/A.swift",
            "@@ -1,3 +1,3 @@",
            " context",
            "-old",
            "+new",
            "@@ -8,0 +9,2 @@",
            "+added",
            "\\ No newline at end of file"
        ].joined(separator: "\n")

        let files = SessionReviewDiffPresentationBuilder.parseFiles(from: diff)
        let file = try #require(files.first)

        #expect(files.count == 1)
        #expect(file.hunks.count == 2)
        #expect(file.hunks[0].header == "@@ -1,3 +1,3 @@")
        #expect(file.hunks[0].lines.map { $0.kind } == [.meta, .context, .removed, .added])
        #expect(file.hunks[1].header == "@@ -8,0 +9,2 @@")
        #expect(file.hunks[1].lines.map { $0.kind } == [.meta, .added, .meta])
    }

    @Test
    func classifyLineDetectsAllKinds() {
        #expect(SessionReviewDiffPresentationBuilder.classifyLine("+line") == .added)
        #expect(SessionReviewDiffPresentationBuilder.classifyLine("-line") == .removed)
        #expect(SessionReviewDiffPresentationBuilder.classifyLine(" line") == .context)
        #expect(SessionReviewDiffPresentationBuilder.classifyLine("+++ b/file.swift") == .meta)
        #expect(SessionReviewDiffPresentationBuilder.classifyLine("--- a/file.swift") == .meta)
        #expect(SessionReviewDiffPresentationBuilder.classifyLine("@@ -1,1 +1,1 @@") == .meta)
    }

    @Test
    func parseFilesReturnsEmptyForNoDiff() {
        #expect(SessionReviewDiffPresentationBuilder.parseFiles(from: "").isEmpty)
        #expect(SessionReviewDiffPresentationBuilder.parseFiles(from: "   \n").isEmpty)
    }

    @Test
    func parsePathUsesRightSideWhenLeftIsDevNull() {
        let path = SessionReviewDiffPresentationBuilder.parsePath(
            fromHeader: "diff --git a/dev/null b/Sources/NewFile.swift"
        )
        #expect(path == "Sources/NewFile.swift")
    }
}
