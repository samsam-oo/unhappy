import Foundation

enum NewSessionDirectoryPathResolver {
    static func normalizedPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "~" : trimmed
    }

    static func normalizedOptionalPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parentDirectory(from rawPath: String) -> String {
        let path = normalizedPath(rawPath)
        if path == "~" || path == "/" {
            return path
        }
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            let components = suffix.split(separator: "/").dropLast()
            if components.isEmpty {
                return "~"
            }
            return "~/" + components.joined(separator: "/")
        }
        let components = path.split(separator: "/").dropLast()
        if components.isEmpty {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }

    static func resolvedPath(current: String, entryName: String) -> String {
        let path = normalizedPath(current)
        let trimmedName = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return path }
        if trimmedName == "." {
            return path
        }
        if trimmedName == ".." {
            return parentDirectory(from: path)
        }
        if trimmedName.hasPrefix("/") {
            return trimmedName
        }
        if path == "/" {
            return "/" + trimmedName
        }
        if path.hasSuffix("/") {
            return path + trimmedName
        }
        if path == "~" {
            return "~/" + trimmedName
        }
        return path + "/" + trimmedName
    }
}
