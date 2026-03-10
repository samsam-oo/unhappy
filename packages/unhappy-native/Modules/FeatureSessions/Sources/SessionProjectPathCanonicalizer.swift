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
        return normalizePOSIXPath(path)
    }

    private static func normalizePOSIXPath(_ rawPath: String) -> String {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        let hasHomePrefix = path == "~" || path.hasPrefix("~/")
        let hasRootPrefix = !hasHomePrefix && path.hasPrefix("/")
        let suffix: Substring
        if hasHomePrefix {
            suffix = path == "~" ? Substring() : path.dropFirst(2)
        } else if hasRootPrefix {
            suffix = path.dropFirst()
        } else {
            suffix = Substring(path)
        }

        var components: [Substring] = []
        for component in suffix.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !hasHomePrefix && !hasRootPrefix {
                    components.append(component)
                }
            default:
                components.append(component)
            }
        }

        let joined = components.map(String.init).joined(separator: "/")
        if hasHomePrefix {
            return joined.isEmpty ? "~" : "~/" + joined
        }
        if hasRootPrefix {
            return joined.isEmpty ? "/" : "/" + joined
        }
        return joined.isEmpty ? "." : joined
    }
}
