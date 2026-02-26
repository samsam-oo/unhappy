import Testing
@testable import FeatureSessionTools

struct SessionFileDiffCommandBuilderTests {
    @Test
    func diffCommandUsesExplicitWorkingDirectoryWhenProvided() {
        let command = SessionFileDiffCommandBuilder.diffCommand(
            filePath: "/repo/Sources/App.swift",
            workingDirectory: "/repo"
        )

        #expect(command == "git -C '/repo' diff --no-ext-diff -- '/repo/Sources/App.swift'")
    }

    @Test
    func parentDirectoryExtractsDirectoryPath() {
        let directory = SessionFileDiffCommandBuilder.parentDirectory(from: "/repo/Sources/App.swift")
        #expect(directory == "/repo/Sources")
    }

    @Test
    func parentDirectoryHandlesRootPath() {
        let directory = SessionFileDiffCommandBuilder.parentDirectory(from: "/file.txt")
        #expect(directory == "/")
    }
}
