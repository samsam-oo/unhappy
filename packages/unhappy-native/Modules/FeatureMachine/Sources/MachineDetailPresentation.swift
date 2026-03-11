import Foundation
import CoreKit

struct MachineDetailField: Equatable, Identifiable, Sendable {
    let key: String
    let value: String

    var id: String { key }
}

struct MachineDetailPresentation: Equatable, Sendable {
    let machineID: String
    let active: Bool
    let stoppedAtText: String?
    let statusText: String
    let activeAtText: String
    let createdAtText: String
    let updatedAtText: String
    let metadataVersionText: String
    let daemonStateVersionText: String
    let metadataCharacterCount: Int
    let metadataPreview: String
    let metadataTruncated: Bool
    let metadataFields: [MachineDetailField]
    let daemonStateCharacterCount: Int
    let daemonStatePreview: String?
    let daemonStateTruncated: Bool
    let daemonStateFields: [MachineDetailField]
}

enum MachineDetailPresentationBuilder {
    static let previewLimit = 2_000
    static let fieldValueLimit = 400

    static func make(
        from machine: APIMachine,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> MachineDetailPresentation {
        let metadataPreview = truncate(machine.metadata, limit: previewLimit)
        let daemonStateRaw = normalizedOptional(machine.daemonState)
        let daemonStatePreview = daemonStateRaw.map { truncate($0, limit: previewLimit) }

        return MachineDetailPresentation(
            machineID: machine.id,
            active: machine.active,
            stoppedAtText: machine.stoppedAt.map(timestampFormatter),
            statusText: machine.active ? "Online" : (machine.isExplicitlyStopped ? "Stopped" : "Unknown"),
            activeAtText: timestampFormatter(machine.activeAt),
            createdAtText: timestampFormatter(machine.createdAt),
            updatedAtText: timestampFormatter(machine.updatedAt),
            metadataVersionText: "\(machine.metadataVersion)",
            daemonStateVersionText: "\(machine.daemonStateVersion)",
            metadataCharacterCount: machine.metadata.count,
            metadataPreview: metadataPreview.value,
            metadataTruncated: metadataPreview.truncated,
            metadataFields: parseJSONFields(raw: machine.metadata),
            daemonStateCharacterCount: daemonStateRaw?.count ?? 0,
            daemonStatePreview: daemonStatePreview?.value,
            daemonStateTruncated: daemonStatePreview?.truncated ?? false,
            daemonStateFields: parseJSONFields(raw: daemonStateRaw ?? "")
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

    private static func normalizedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncate(_ value: String, limit: Int) -> (value: String, truncated: Bool) {
        guard value.count > limit else { return (value, false) }
        return (String(value.prefix(limit)), true)
    }

    private static func parseJSONFields(raw: String) -> [MachineDetailField] {
        guard !raw.isEmpty else { return [] }
        guard let data = raw.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        guard let dictionary = object as? [String: Any] else { return [] }

        return dictionary.keys.sorted().map { key in
            MachineDetailField(
                key: key,
                value: stringify(dictionary[key])
            )
        }
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return truncate(string, limit: fieldValueLimit).value
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return truncate(string, limit: fieldValueLimit).value
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return truncate(String(describing: value), limit: fieldValueLimit).value
    }
}
