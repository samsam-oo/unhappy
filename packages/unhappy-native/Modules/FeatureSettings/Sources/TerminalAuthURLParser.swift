import Foundation

struct TerminalAuthRequest: Equatable, Sendable {
    let publicKey: String
}

enum TerminalAuthURLParser {
    static func parse(_ raw: String) -> TerminalAuthRequest? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let components = URLComponents(string: trimmed)
        else {
            return nil
        }

        if isNativeTerminalURL(components) || isWebTerminalConnectURL(components) {
            return extractPublicKey(from: components)
        }

        return nil
    }

    private static func isNativeTerminalURL(_ components: URLComponents) -> Bool {
        guard components.scheme == "unhappy" else { return false }
        let host = components.host?.lowercased()
        let path = components.path.lowercased()
        return host == "terminal" || path == "/terminal"
    }

    private static func isWebTerminalConnectURL(_ components: URLComponents) -> Bool {
        guard
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }

        let path = components.path.lowercased()
        return path == "/terminal/connect" || path == "/terminal"
    }

    private static func extractPublicKey(from components: URLComponents) -> TerminalAuthRequest? {
        if let queryItems = components.queryItems {
            if let value = extractPublicKey(from: queryItems) {
                return TerminalAuthRequest(publicKey: value)
            }
        }

        if
            let encodedQuery = components.percentEncodedQuery,
            let value = normalizedValue(encodedQuery.removingPercentEncoding ?? encodedQuery)
        {
            return TerminalAuthRequest(publicKey: value)
        }

        if
            let fragment = components.percentEncodedFragment,
            let value = extractPublicKey(fromFragment: fragment)
        {
            return TerminalAuthRequest(publicKey: value)
        }

        return nil
    }

    private static func extractPublicKey(from queryItems: [URLQueryItem]) -> String? {
        for key in ["publicKey", "key", "k"] {
            if let item = queryItems.first(where: { $0.name == key }),
               let value = normalizedValue(item.value) {
                return value
            }
        }
        return nil
    }

    private static func extractPublicKey(fromFragment fragment: String) -> String? {
        let decodedFragment = fragment.removingPercentEncoding ?? fragment
        let trimmedFragment = decodedFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFragment.isEmpty else { return nil }

        let fragmentQuery = trimmedFragment.hasPrefix("?")
            ? String(trimmedFragment.dropFirst())
            : trimmedFragment

        if
            let queryComponents = URLComponents(string: "unhappy://fragment?\(fragmentQuery)"),
            let queryItems = queryComponents.queryItems,
            let value = extractPublicKey(from: queryItems)
        {
            return value
        }

        if !fragmentQuery.contains("="), let value = normalizedValue(fragmentQuery) {
            return value
        }

        return nil
    }

    private static func normalizedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value
    }
}
