import SwiftUI
import CoreKit

struct SessionInfoOverviewSections: View {
    let presentation: SessionInfoPresentation

    var body: some View {
        sessionSection
        metadataSection
        agentStateSection
    }

    private var sessionSection: some View {
        Section("Session") {
            LabeledContent("ID") {
                Text(presentation.sessionID)
                    .font(.footnote.monospaced())
            }
            LabeledContent("Title") {
                Text(presentation.title)
                    .foregroundStyle(presentation.isFallbackTitle ? .secondary : .primary)
            }
            if let machineDisplayName = presentation.machineDisplayName {
                LabeledContent("Machine") {
                    Text(machineDisplayName)
                        .lineLimit(1)
                }
            }
            if let machineIdentifier = presentation.machineIdentifier {
                LabeledContent("Machine ID") {
                    Text(machineIdentifier)
                        .font(.footnote.monospaced())
                }
            }
            LabeledContent("Status") {
                Text(presentation.active ? "Active" : "Inactive")
                    .foregroundStyle(presentation.active ? Color.green : Color.secondary)
            }
            if let sequenceText = presentation.sequenceText {
                LabeledContent("Sequence") {
                    Text(sequenceText)
                        .font(.footnote.monospaced())
                }
            }
            LabeledContent("Created") { Text(presentation.createdAtText) }
            LabeledContent("Active At") { Text(presentation.activeAtText) }
            LabeledContent("Updated") { Text(presentation.updatedAtText) }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            LabeledContent("Metadata Version") {
                Text(presentation.metadataVersionText)
                    .font(.footnote.monospaced())
            }
            if let agentStateVersionText = presentation.agentStateVersionText {
                LabeledContent("Agent State Version") {
                    Text(agentStateVersionText)
                        .font(.footnote.monospaced())
                }
            }
            LabeledContent("Metadata Size") {
                Text("\(presentation.metadataCharacterCount) chars")
                    .font(.footnote.monospaced())
            }
            if let keyPreview = presentation.dataEncryptionKeyPreview {
                LabeledContent("Data Key") {
                    Text(keyPreview)
                        .font(.footnote.monospaced())
                }
            } else {
                LabeledContent("Data Key") {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            }

            if !presentation.metadataFields.isEmpty {
                Text("Metadata Fields")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(presentation.metadataFields) { field in
                    SessionInfoKeyValueBlock(field: field)
                }
            }

            Text(presentation.metadataPreview)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .lineLimit(nil)

            if presentation.metadataTruncated {
                Text("Metadata preview is truncated to first \(SessionInfoPresentationBuilder.metadataPreviewLimit) chars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var agentStateSection: some View {
        if presentation.agentStatePreview != nil || !presentation.agentStateFields.isEmpty {
            Section("Agent State") {
                LabeledContent("Size") {
                    Text("\(presentation.agentStateCharacterCount) chars")
                        .font(.footnote.monospaced())
                }
                if !presentation.agentStateFields.isEmpty {
                    Text("Parsed Fields")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(presentation.agentStateFields) { field in
                        SessionInfoKeyValueBlock(field: field)
                    }
                }
                if let preview = presentation.agentStatePreview {
                    Text(preview)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                if presentation.agentStateTruncated {
                    Text("Agent state preview is truncated to first \(SessionInfoPresentationBuilder.metadataPreviewLimit) chars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SessionInfoKeyValueBlock: View {
    let field: SessionInfoPayloadField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(field.value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .lineLimit(nil)
        }
        .padding(.vertical, 2)
    }
}
