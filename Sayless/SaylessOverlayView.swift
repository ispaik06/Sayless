import SwiftUI

struct SaylessOverlayView: View {
    @ObservedObject var state: OverlayState
    let onSelect: (Suggestion, FocusedTextContext) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch state.content {
            case .suggestions(let context, let items):
                if !context.value.isEmpty {
                    Text(context.value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelect(item, context)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(item.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green.opacity(0.95))
                                    .frame(width: 76, alignment: .leading)

                                Text(item.text)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(SuggestionButtonStyle(isSelected: state.selectedIndex == index))
                        .onHover { isHovering in
                            if isHovering {
                                state.selectedIndex = index
                            }
                        }
                    }
                }

            case .notice(let title, let message, let buttonTitle):
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let buttonTitle {
                        Button {
                            openAccessibilitySettings()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(buttonTitle)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(.green.opacity(0.32), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 430, alignment: .leading)
        .background(GlassBackground())
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)

            Text("Sayless")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)

            if let roomTitle = roomTitle, !roomTitle.isEmpty {
                Text(roomTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 2)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var roomTitle: String? {
        guard case .suggestions(let context, _) = state.content else {
            return nil
        }

        return context.windowTitle
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct SuggestionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return .white.opacity(0.18)
        }

        if isSelected {
            return .green.opacity(0.16)
        }

        return .white.opacity(0.08)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed || isSelected {
            return .green.opacity(0.36)
        }

        return .white.opacity(0.11)
    }
}

private struct GlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.14))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 18)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
