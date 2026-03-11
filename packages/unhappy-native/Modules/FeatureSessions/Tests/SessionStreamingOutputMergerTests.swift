import Foundation
import Testing
@testable import FeatureSessions
import SessionKit

struct SessionStreamingOutputMergerTests {
    @Test
    func mergeSnapshotChunkReplacesPrefix() {
        let merged = SessionStreamingOutputMerger.merge(
            existing: "Investigating",
            chunk: "Investigating issue"
        )

        #expect(merged == "Investigating issue")
    }

    @Test
    func mergeWordBoundaryWithoutLeadingSpaceAddsSeparator() {
        let merged = SessionStreamingOutputMerger.merge(
            existing: "I'm",
            chunk: "noticing"
        )

        #expect(merged == "I'm noticing")
    }

    @Test
    func mergeOverlapStillAddsWordBoundaryWhenNeeded() {
        let merged = SessionStreamingOutputMerger.merge(
            existing: "I'm",
            chunk: "mnoticing"
        )

        #expect(merged == "I'm noticing")
    }
}
