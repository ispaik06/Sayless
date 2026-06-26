import SwiftUI

struct ShortcutRecorderView: View {
    let title: String
    let subtitle: String
    let requiresModifier: Bool
    @Binding var shortcut: KeyboardShortcutSpec?

    @State private var isRecording = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isRecording ? .green.opacity(0.16) : .white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(isRecording ? .green.opacity(0.38) : .white.opacity(0.14), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "record.circle" : "keyboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isRecording ? .green : .secondary)

                        Text(displayText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isRecording ? .primary : shortcut == nil ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)

                    ShortcutCaptureView(
                        isRecording: $isRecording,
                        requiresModifier: requiresModifier,
                        onRecord: { recorded in
                            shortcut = recorded
                            errorText = nil
                        },
                        onInvalid: {
                            errorText = requiresModifier
                                ? "Use at least one modifier, like ⌥, ⇧, ⌘, or ⌃."
                                : "Press a valid key."
                        }
                    )
                    .allowsHitTesting(false)
                }
                .frame(height: 38)

                Button(isRecording ? "Cancel" : "Record") {
                    errorText = nil
                    isRecording.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if shortcut != nil {
                    Button("Clear") {
                        shortcut = nil
                        errorText = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(errorText ?? subtitle)
                .font(.system(size: 12))
                .foregroundColor(errorText == nil ? .secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayText: String {
        if isRecording {
            return "Press a shortcut..."
        }

        return shortcut?.title ?? title
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let requiresModifier: Bool
    let onRecord: (KeyboardShortcutSpec) -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onKeyDown = handleKeyDown
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onKeyDown = handleKeyDown

        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isRecording else {
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            return
        }

        guard let shortcut = KeyboardShortcutSpec.make(from: event, requiresModifier: requiresModifier) else {
            onInvalid()
            return
        }

        onRecord(shortcut)
        isRecording = false
    }
}

private final class RecorderNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
