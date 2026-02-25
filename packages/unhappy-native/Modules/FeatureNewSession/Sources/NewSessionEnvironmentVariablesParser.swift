import Foundation

enum NewSessionEnvironmentVariablesParser {
    static func parse(_ raw: String) throws -> [String: String] {
        var output: [String: String] = [:]
        let lines = raw.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") { continue }

            guard let separator = trimmed.firstIndex(of: "=") else {
                throw NewSessionError.invalidEnvironmentVariable(
                    line: index + 1,
                    value: trimmed
                )
            }

            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: separator)
            let value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw NewSessionError.invalidEnvironmentVariable(
                    line: index + 1,
                    value: trimmed
                )
            }

            output[key] = value
        }

        return output
    }
}
