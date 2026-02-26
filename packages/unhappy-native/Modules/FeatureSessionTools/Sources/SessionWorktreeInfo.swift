import Foundation

struct SessionWorktreeInfo: Equatable, Sendable {
    let worktreePath: String
    let basePath: String
    let worktreeName: String

    private static let worktreeSegmentPOSIX = "/.unhappy/worktree/"
    private static let worktreeSegmentWindows = "\\.unhappy\\worktree\\"

    static func extract(from path: String) -> SessionWorktreeInfo? {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let indexAndLength: (String.Index, Int)?
        if let index = normalized.range(of: worktreeSegmentPOSIX)?.lowerBound {
            indexAndLength = (index, worktreeSegmentPOSIX.count)
        } else if let index = normalized.range(of: worktreeSegmentWindows)?.lowerBound {
            indexAndLength = (index, worktreeSegmentWindows.count)
        } else {
            indexAndLength = nil
        }

        guard let (startIndex, segmentLength) = indexAndLength else { return nil }
        let basePath = String(normalized[..<startIndex])
        guard !basePath.isEmpty else { return nil }

        let afterSegment = String(normalized[normalized.index(startIndex, offsetBy: segmentLength)...])
        let worktreeName = afterSegment.split(whereSeparator: { $0 == "/" || $0 == "\\" }).first.map(String.init)
        guard let worktreeName, !worktreeName.isEmpty else { return nil }

        return SessionWorktreeInfo(
            worktreePath: normalized,
            basePath: basePath,
            worktreeName: worktreeName
        )
    }
}
