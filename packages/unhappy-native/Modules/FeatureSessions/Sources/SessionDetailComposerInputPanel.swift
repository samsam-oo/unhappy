import SwiftUI
import CoreKit

struct SessionComposerInputPanel: View {
    let isKeyboardActive: Bool
    let colorScheme: ColorScheme
    let isSending: Bool
    let queuedComposerMessages: [String]
    let applyModelOverride: Bool
    let selectedModelOverrideOption: String
    let customModelOverrideOption: String
    let sendErrorMessage: String?
    let focusedComposerField: FocusState<SessionDetailView.SessionComposerFocusField?>.Binding
    @Binding var draftMessage: String
    @Binding var modelOverrideDraft: String
    let onQueue: () -> Void
    let onSend: () -> Void
    let onEditQueuedMessage: (_ queueIndex: Int, _ fallbackText: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isKeyboardActive ? 8 : 10) {
            if !queuedComposerMessages.isEmpty {
                queuePreviewCard
            }

            composerTextField
            actionButtonsRow

            if applyModelOverride && selectedModelOverrideOption == customModelOverrideOption {
                customModelField
            }

            if let sendErrorMessage, !sendErrorMessage.isEmpty {
                Text(sendErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var queuePreviewCard: some View {
        VStack(alignment: .leading, spacing: isKeyboardActive ? 6 : 8) {
            let visibleQueuedMessages = Array(queuedComposerMessages.suffix(3))
            let hiddenCount = max(0, queuedComposerMessages.count - visibleQueuedMessages.count)
            let visibleStartIndex = max(0, queuedComposerMessages.count - visibleQueuedMessages.count)

            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
                Text("Steer Stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer(minLength: 0)
                Text(queuedComposerMessages.count == 1 ? "1 queued" : "\(queuedComposerMessages.count) queued")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
            }

            if !isKeyboardActive {
                ForEach(Array(visibleQueuedMessages.enumerated()), id: \.offset) { index, text in
                    let queueIndex = visibleStartIndex + index
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(AppPalette.secondaryText)
                        Text(text)
                            .font(.footnote)
                            .lineLimit(1)
                            .foregroundStyle(AppPalette.primaryText)
                        Spacer(minLength: 0)
                        Button("Edit") {
                            onEditQueuedMessage(queueIndex, text)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }

                    if index < visibleQueuedMessages.count - 1 {
                        Rectangle()
                            .fill(AppPalette.chromeDivider.opacity(0.7))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.controlSurface.opacity(colorScheme == .dark ? 0.72 : 0.9))
        )
    }

    private var composerTextField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            TextField("Ask for follow-up changes", text: $draftMessage, axis: .vertical)
                .lineLimit(isKeyboardActive ? 1...3 : 1...4)
                .textInputAutocapitalization(.sentences)
                .font(.subheadline.weight(.medium))
                .focused(focusedComposerField, equals: .message)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isKeyboardActive ? 9 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.composerFieldBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    focusedComposerField.wrappedValue == .message
                        ? AppPalette.accent.opacity(0.55)
                        : AppPalette.composerFieldStroke.opacity(0.4),
                    lineWidth: focusedComposerField.wrappedValue == .message ? 1.5 : 1
                )
        }
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Button(action: onQueue) {
                Label("Queue", systemImage: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppPalette.controlSurface)
                    )
            }
            .buttonStyle(PressableScaleButtonStyle())
            .disabled(isSending)

            Button(action: onSend) {
                Label(isSending ? "Sending…" : "Send", systemImage: "paperplane.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppPalette.sendGradientTop,
                                        AppPalette.sendGradientBottom,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: AppPalette.accent.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(PressableScaleButtonStyle())
            .disabled(isSending)
        }
    }

    private var customModelField: some View {
        TextField("Custom model id", text: $modelOverrideDraft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.footnote.monospaced())
            .focused(focusedComposerField, equals: .customModel)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppPalette.controlSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        focusedComposerField.wrappedValue == .customModel
                            ? AppPalette.accent.opacity(0.55)
                            : AppPalette.composerFieldStroke.opacity(0.4),
                        lineWidth: focusedComposerField.wrappedValue == .customModel ? 1.5 : 1
                    )
            }
    }
}
