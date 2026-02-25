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
            components.scheme == "unhappy",
            components.host == "terminal"
        else {
            return nil
        }

        if let keyItem = components.queryItems?.first(where: { $0.name == "key" }),
           let value = keyItem.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return TerminalAuthRequest(publicKey: value)
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
