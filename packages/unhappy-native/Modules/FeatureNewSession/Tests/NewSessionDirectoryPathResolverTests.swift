import Testing
@testable import FeatureNewSession

struct NewSessionDirectoryPathResolverTests {
    @Test
    func parentDirectoryUsesAbsolutePathSegments() {
        #expect(
            NewSessionDirectoryPathResolver.parentDirectory(
                from: "/Users/skyline23/Downloads/unhappy"
            ) == "/Users/skyline23/Downloads"
        )
    }

    @Test
    func parentDirectoryUsesHomeRelativePathSegments() {
        #expect(
            NewSessionDirectoryPathResolver.parentDirectory(
                from: "~/Downloads/unhappy"
            ) == "~/Downloads"
        )
    }

    @Test
    func resolvedPathAppendsDirectoryNameToCurrentPath() {
        #expect(
            NewSessionDirectoryPathResolver.resolvedPath(
                current: "/Users/skyline23/Downloads",
                entryName: "unhappy"
            ) == "/Users/skyline23/Downloads/unhappy"
        )
    }
}
