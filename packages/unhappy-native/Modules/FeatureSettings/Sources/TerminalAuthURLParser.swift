import Foundation

struct TerminalAuthRequest: Equatable, Sendable {
    let publicKey: String
}

enum TerminalAuthURLParser {
    static func parse(_ raw: String) -> TerminalAuthRequest? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let components = URLComponents(string: trimmed),
            components.scheme == "unhappy"
        else {
            return nil
        }

        let host = components.host?.lowercased()
        let path = components.path.lowercased()
        guard host == "terminal" || path == "/terminal" else {
            return nil
        }

        if let queryItems = components.queryItems {
            for key in ["publicKey", "key", "k"] {
                if let item = queryItems.first(where: { $0.name == key }),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return TerminalAuthRequest(publicKey: value)
                }
            }
        }

        guard
            let encodedQuery = components.percentEncodedQuery,
            !encodedQuery.isEmpty
        else {
            return nil
        }

        let decodedQuery = encodedQuery.removingPercentEncoding ?? encodedQuery
        let value = decodedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return TerminalAuthRequest(publicKey: value)
    }
}
