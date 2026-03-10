import Testing
@testable import FeatureSessions

struct SessionProjectPathCanonicalizerTests {
    @Test
    func canonicalPathPreservesRemoteHomeRelativePaths() {
        let result = SessionProjectPathCanonicalizer.canonicalPath("~/Downloads/shadow-client")

        #expect(result == "~/Downloads/shadow-client")
    }

    @Test
    func canonicalPathExpandsTildeOnlyWhenRemoteHomeIsProvided() {
        let result = SessionProjectPathCanonicalizer.canonicalPath(
            "~/Downloads/shadow-client",
            homeDirectory: "/Users/dstadmin"
        )

        #expect(result == "/Users/dstadmin/Downloads/shadow-client")
    }

    @Test
    func canonicalPathNormalizesDotSegmentsWithoutExpandingTilde() {
        let result = SessionProjectPathCanonicalizer.canonicalPath(
            "~/Downloads/./client/../shadow-client/"
        )

        #expect(result == "~/Downloads/shadow-client")
    }
}
