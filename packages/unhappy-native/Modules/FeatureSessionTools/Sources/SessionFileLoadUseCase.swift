import Foundation
import CoreKit

public protocol SessionFileLoadingAction: Sendable {
    func loadFile(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> String
}

public enum SessionFileLoadError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingPath
    case invalidBase64Content
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .missingPath:
            return "Path is required"
        case .invalidBase64Content:
            return "File payload is not valid base64"
        case .failed(let message):
            return message
        }
    }
}

public actor SessionFileLoadUseCase: SessionFileLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let path: String
    }

    private static let maxRenderedBytes = 300_000

    private let service: any SessionFileReading
    private var inFlightTasks: [RequestKey: Task<String, Error>] = [:]

    public init(service: any SessionFileReading) {
        self.service = service
    }

    public func loadFile(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> String {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionFileLoadError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionFileLoadError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionFileLoadError.missingSessionID
        }

        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionFileLoadError.missingPath
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            path: normalizedPath
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<String, Error> {
            let result = try await service.readFile(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                path: normalizedPath
            )

            guard result.success else {
                let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SessionFileLoadError.failed(
                    message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to read file"
                )
            }

            guard let encoded = result.content else {
                throw SessionFileLoadError.failed(message: "File response did not contain content")
            }

            guard let data = Data(base64Encoded: encoded) else {
                throw SessionFileLoadError.invalidBase64Content
            }

            if data.count > Self.maxRenderedBytes {
                let prefix = data.prefix(Self.maxRenderedBytes)
                let truncatedText = String(decoding: prefix, as: UTF8.self)
                return "\(truncatedText)\n\n[truncated: showing first \(Self.maxRenderedBytes) bytes]"
            }

            return String(decoding: data, as: UTF8.self)
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
