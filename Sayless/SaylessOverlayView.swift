import SwiftUI

struct SaylessOverlayView: View {
    @ObservedObject var state: OverlayState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isCustomInstructionFocused: Bool
    @State private var appeared = false
    let onSelect: (Suggestion, FocusedTextContext) -> Void
    let onClose: () -> Void
    let onRefresh: () -> Void
    let onAdjustment: (SuggestionAdjustmentOption) -> Void
    let onCustomInstructionSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch state.content {
            case .generating(let context):
                if !context.value.isEmpty {
                    composingPreview(context.value)
                }

                GeneratingSuggestionsView(
                    title: "Generating replies",
                    subtitle: "Reading the latest visible messages"
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)

            case .generationFailed(let context, let message):
                if !context.value.isEmpty {
                    composingPreview(context.value)
                }

                GenerationFailedView(message: message)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)

            case .suggestions(let context, let batches, let activeBatchIndex):
                if !context.value.isEmpty {
                    composingPreview(context.value)
                }

                suggestionsView(context: context, batches: batches, activeBatchIndex: activeBatchIndex)

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
        .frame(width: 470, alignment: .leading)
        .background(GlassBackground())
        .opacity(appeared ? 1 : 0)
        .scaleEffect(presentationScale, anchor: .center)
        .offset(y: presentationOffset)
        .onAppear {
            appeared = state.isPresented
        }
        .onChange(of: state.isPresented) { _, isPresented in
            if isPresented {
                startAppearanceAnimation()
            } else {
                hideAppearanceAnimation()
            }
        }
        .onExitCommand {
            if state.isCustomInstructionFocused {
                state.isCustomInstructionFocused = false
            } else {
                onClose()
            }
        }
        .onChange(of: state.isCustomInstructionFocused) { _, isFocused in
            isCustomInstructionFocused = isFocused
        }
        .onChange(of: isCustomInstructionFocused) { _, isFocused in
            state.isCustomInstructionFocused = isFocused
        }
    }

    private var presentationScale: CGFloat {
        if reduceMotion {
            return 1
        }

        if appeared {
            return 1
        }

        return state.isDismissing ? 0.985 : 0.95
    }

    private var presentationOffset: CGFloat {
        if reduceMotion {
            return 0
        }

        if appeared {
            return 0
        }

        return -4
    }

    private var showAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.1)
        }

        return .spring(response: 0.19, dampingFraction: 0.74, blendDuration: 0)
    }

    private var hideAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.14)
    }

    private func startAppearanceAnimation() {
        appeared = false

        DispatchQueue.main.async {
            guard state.isPresented else {
                return
            }

            withAnimation(showAnimation) {
                appeared = true
            }
        }
    }

    private func hideAppearanceAnimation() {
        withAnimation(hideAnimation) {
            appeared = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.message")
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

            if state.content.focusedContext != nil {
                if state.hasNewerVisibleMessages {
                    NewMessageBadge()
                }

                Button(action: onRefresh) {
                    RefreshButtonLabel(shortcutTitle: state.refreshShortcutTitle)
                }
                .buttonStyle(.plain)
                .help("AI 답장 새로 받기")
            }

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
        state.content.displayTitle
    }

    private func suggestionsView(
        context: FocusedTextContext,
        batches: [SuggestionBatch],
        activeBatchIndex: Int
    ) -> some View {
        let clampedBatchIndex = min(max(activeBatchIndex, 0), max(batches.count - 1, 0))
        let items = batches.indices.contains(clampedBatchIndex) ? batches[clampedBatchIndex].suggestions : []

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Tab / Shift Tab")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if batches.count > 1 {
                    Text("\(clampedBatchIndex + 1)/\(batches.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green.opacity(0.95))
                }

                Spacer(minLength: 0)

                if state.isGeneratingMore {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                    Text("새로 받는 중")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
                                .lineLimit(1)
                                .frame(width: 82, alignment: .leading)

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
                    .buttonStyle(
                        SuggestionButtonStyle(
                            isSelected: state.keyboardFocus == .suggestions && state.selectedIndex == index
                        )
                    )
                    .onHover { isHovering in
                        if isHovering {
                            state.keyboardFocus = .suggestions
                            state.selectedIndex = index
                            state.selectedAdjustmentIndex = nil
                        }
                    }
                }
            }

            adjustmentBar

            if state.isCustomInstructionVisible {
                customInstructionInput
            }
        }
    }

    private var adjustmentBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(SuggestionAdjustmentOption.allCases.enumerated()), id: \.element.id) { index, option in
                let isUsed = option != .custom && state.usedAdjustmentOptions.contains(option)
                Button {
                    guard !isUsed else {
                        return
                    }

                    state.keyboardFocus = .adjustments
                    onAdjustment(option)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isUsed ? "checkmark" : option.systemImage)
                            .font(.system(size: 10, weight: .bold))
                        Text(option.title)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(
                    AdjustmentButtonStyle(
                        isSelected: state.keyboardFocus == .adjustments && state.selectedAdjustmentIndex == index,
                        isUsed: isUsed
                    )
                )
                .disabled(isUsed)
            }
        }
    }

    private var customInstructionInput: some View {
        HStack(spacing: 8) {
            TextField("원하는 느낌, 길이, 말투, 언어 입력", text: $state.customInstructionDraft)
                .textFieldStyle(.plain)
                .focused($isCustomInstructionFocused)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.green.opacity(0.26), lineWidth: 1)
                )
                .onSubmit(onCustomInstructionSubmit)
                .onExitCommand {
                    state.isCustomInstructionFocused = false
                }

            Button {
                onCustomInstructionSubmit()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 34)
                    .background(.green.opacity(0.34), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func composingPreview(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct GenerationFailedView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("추천 생성에 실패했습니다")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(message ?? "다시 시도하거나 백엔드 연결을 확인해 주세요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        )
    }
}

private struct GeneratingSuggestionsView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            LoadingDotsView()
                .frame(height: 28)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        )
    }
}

private struct LoadingDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { index in
                    let progress = dotProgress(at: timeline.date, index: index)
                    Circle()
                        .fill(.green.opacity(reduceMotion ? 0.72 : 0.42 + 0.52 * progress))
                        .frame(width: 8, height: 8)
                        .offset(y: reduceMotion ? 0 : CGFloat(7 - 14 * progress))
                }
            }
        }
    }

    private func dotProgress(at date: Date, index: Int) -> Double {
        let interval = date.timeIntervalSinceReferenceDate
        let shifted = interval * 1.85 - Double(index) * 0.22
        return (sin(shifted * Double.pi * 2) + 1) / 2
    }
}

private struct NewMessageBadge: View {
    @State private var isLit = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(isLit ? 0.9 : 0.25), radius: isLit ? 7 : 2)

            Text("새 메시지 · ⌘⇧R")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.green.opacity(isLit ? 1 : 0.62))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.green.opacity(isLit ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.green.opacity(isLit ? 0.38 : 0.16), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                isLit = true
            }
        }
    }
}

private struct RefreshButtonLabel: View {
    let shortcutTitle: String

    var body: some View {
        HStack(spacing: 7) {
            IntelligenceGlyph()

            VStack(alignment: .leading, spacing: 0) {
                Text("새로 받기")
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(1)
                Text(shortcutTitle)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.86))
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 32)
        .background(
            LinearGradient(
                colors: [
                    .green.opacity(0.44),
                    .mint.opacity(0.32),
                    Color(red: 0.12, green: 0.52, blue: 0.34).opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.mint.opacity(0.36), lineWidth: 1)
        )
        .shadow(color: .green.opacity(0.18), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct IntelligenceGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.18))
                .frame(width: 22, height: 22)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .mint,
                            .green,
                            Color(red: 0.70, green: 0.96, blue: 0.56),
                            .mint
                        ],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 21, height: 21)

            Image(systemName: "lasso.badge.sparkles")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.94))
        }
        .frame(width: 23, height: 23)
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

private struct AdjustmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isUsed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
    }

    private var foregroundColor: Color {
        if isUsed {
            return .secondary.opacity(0.52)
        }

        return isSelected ? .primary : .secondary
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return .white.opacity(0.18)
        }

        if isUsed {
            return .white.opacity(0.035)
        }

        return isSelected ? .green.opacity(0.14) : .white.opacity(0.06)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isUsed {
            return .white.opacity(0.07)
        }

        if isPressed || isSelected {
            return .green.opacity(0.3)
        }

        return .white.opacity(0.1)
    }
}

private struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(.regularMaterial)
            shape
                .fill(panelTint)
            shape
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: shadowColor, radius: 36, x: 0, y: 14)
    }

    private var panelTint: Color {
        colorScheme == .dark ? .black.opacity(0.10) : .white.opacity(0.20)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.30) : .black.opacity(0.16)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
