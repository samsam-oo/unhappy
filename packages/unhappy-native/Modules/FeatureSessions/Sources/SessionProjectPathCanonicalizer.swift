import Foundation

enum SessionProjectPathCanonicalizer {
    static func canonicalPath(
        _ rawPath: String?,
        homeDirectory: String? = nil
    ) -> String? {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        var path = rawPath.replacingOccurrences(of: "\\", with: "/")
        let normalizedHomeDirectory = homeDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")

        if path == "~", let normalizedHomeDirectory, !normalizedHomeDirectory.isEmpty {
            path = normalizedHomeDirectory
        } else if path.hasPrefix("~/"),
                  let normalizedHomeDirectory,
                  !normalizedHomeDirectory.isEmpty {
            path = normalizedHomeDirectory + "/" + path.dropFirst(2)
        }

        if path == "/" {
            return path
        }

        let standardized = (path as NSString).standardizingPath
        var normalized = standardized.isEmpty ? path : standardized
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
