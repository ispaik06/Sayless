import AppKit
import ClerkKit
import ClerkKitUI
import Combine
import SwiftUI

final class HomeWindowController: NSWindowController {
    private let appModel: AppModel
    private let navigation = HomeNavigation()

    init(appModel: AppModel) {
        self.appModel = appModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let hostingView = FullSizeHostingView(
            rootView: HomeView()
                .environmentObject(appModel)
                .environmentObject(navigation)
                .environmentObject(AuthSessionManager.shared)
                .environmentObject(AppLanguageSettings.shared)
                .environment(AuthSessionManager.shared.clerk)
                .ignoresSafeArea()
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let glassContainer = PreferencesGlassContainerView()
        glassContainer.material = .underWindowBackground
        glassContainer.blendingMode = .behindWindow
        glassContainer.state = .followsWindowActiveState
        glassContainer.wantsLayer = true
        glassContainer.layer?.backgroundColor = NSColor.clear.cgColor
        glassContainer.layer?.cornerRadius = WindowStyling.preferencesCornerRadius
        glassContainer.layer?.cornerCurve = .continuous
        glassContainer.layer?.masksToBounds = true
        glassContainer.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassContainer.bottomAnchor)
        ])

        window.contentView = glassContainer
        WindowStyling.applyHomeGlass(to: window)
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showHome(section: HomeSection = .home) {
        guard let window else {
            return
        }

        navigation.selectedSection = section

        if !window.isVisible {
            window.center()
        }

        AppActivationManager.shared.showAppWindow(window) { window in
            WindowStyling.applyHomeGlass(to: window)
        }
    }
}

final class HomeNavigation: ObservableObject {
    @Published var selectedSection: HomeSection = .home
}

enum HomeSection: String, CaseIterable, Identifiable {
    case home
    case preferences
    case guide
    case account

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .preferences: "Preferences"
        case .guide: "Guide"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .preferences: "slider.horizontal.3"
        case .guide: "sparkles"
        case .account: "person.crop.circle"
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var navigation: HomeNavigation
    @EnvironmentObject private var authSession: AuthSessionManager
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(Clerk.self) private var clerk
    @StateObject private var settings = ReplyStyleSettings.shared
    @StateObject private var accountStatus = AccountStatusService()
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var authSheetMode: HomeAuthSheetMode?
    @State private var isProfilePresented = false
    @State private var isAccountPanelHovered = false

    private func tr(_ english: String, _ korean: String) -> String {
        languageSettings.text(english, korean)
    }

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                state: .followsWindowActiveState
            )
            .ignoresSafeArea()

            HStack(spacing: 10) {
                sidebar
                ScrollView {
                    selectedContent
                        .padding(.top, 24)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HomePanelBackground(material: .hudWindow, tintOpacity: 0.028))
            }
            .padding(10)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(
            minWidth: 830,
            idealWidth: 920,
            maxWidth: .infinity,
            minHeight: 640,
            idealHeight: 720,
            maxHeight: .infinity
        )
        .clipShape(RoundedRectangle(cornerRadius: WindowStyling.preferencesCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WindowStyling.preferencesCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .background(WindowAccessor { window in
            WindowStyling.applyHomeGlass(to: window)
        })
        .sheet(item: $authSheetMode) { mode in
            AuthView(mode: mode.clerkMode)
                .environment(authSession.clerk)
        }
        .sheet(isPresented: $isProfilePresented) {
            UserProfileView()
                .environment(authSession.clerk)
        }
        .task(id: clerk.user?.id) {
            if clerk.user != nil {
                await accountStatus.load()
            } else {
                accountStatus.reset()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "ellipsis.message")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.68, green: 0.8, blue: 0.84),
                                Color(red: 0.73, green: 0.89, blue: 0.53),
                                Color(red: 0.69, green: 1.0, blue: 0.49),
                                Color(red: 0.5, green: 1.0, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Sayless")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.bottom, 6)

            ForEach(HomeSection.allCases) { section in
                HomeSidebarItem(
                    icon: section.systemImage,
                    title: sectionTitle(section),
                    selected: navigation.selectedSection == section
                ) {
                    navigation.selectedSection = section
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 70)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 162)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HomePanelBackground(material: .sidebar, tintOpacity: 0.035))
    }

    private func sectionTitle(_ section: HomeSection) -> String {
        switch section {
        case .home: tr("Home", "홈")
        case .preferences: tr("Preferences", "설정")
        case .guide: tr("Guide", "가이드")
        case .account: tr("Account", "계정")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch navigation.selectedSection {
        case .home:
            homeContent
        case .preferences:
            preferencesContent
        case .guide:
            guideContent
        case .account:
            accountContent
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard
            supportedPlatformsCard
            styleSlotsCard
            personalStyleCard
            quickActions
        }
    }

    private var heroCard: some View {
        LiquidHomeCard(
            accent: [Color(red: 0.55, green: 0.95, blue: 0.72), Color(red: 0.46, green: 0.75, blue: 1.0)],
            reactsToHover: false
        ) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.69, green: 1.0, blue: 0.56),
                                        Color(red: 0.48, green: 0.88, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "ellipsis.message.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.black.opacity(0.72))
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sayless Home")
                            .font(.system(size: 27, weight: .bold))
                        Text(tr("Shape the reply controls and your default voice.", "답변 버튼과 기본 말투를 원하는 방식으로 설정하세요."))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 260)
                }

                Button {
                    navigation.selectedSection = .account
                } label: {
                    accountHeroPanel
                }
                .buttonStyle(.plain)
                .scaleEffect(isAccountPanelHovered ? 1.025 : 1.0)
                .shadow(color: .black.opacity(isAccountPanelHovered ? 0.18 : 0.08), radius: isAccountPanelHovered ? 18 : 8, x: 0, y: isAccountPanelHovered ? 10 : 4)
                .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isAccountPanelHovered)
                .onHover { hovering in
                    isAccountPanelHovered = hovering
                }
            }
        }
    }

    private var accountHeroPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: clerk.user == nil ? "person.crop.circle.badge.plus" : "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(clerk.user == nil ? Color.secondary : Color.green)

                Text(tr("Account", "계정"))
                    .font(.system(size: 14, weight: .bold))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let configurationError = authSession.configurationError {
                Text(configurationError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if clerk.user != nil {
                Text(authSession.userDisplayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let account = accountStatus.account {
                    Text("\(account.plan.capitalized) · \(account.usage.daily.requests) \(tr("today", "오늘"))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(tr("Sign in to use authenticated suggestions.", "로그인하면 인증된 추천을 사용할 수 있어요."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 242, alignment: .leading)
        .background(.white.opacity(isAccountPanelHovered ? 0.15 : 0.075), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.68, green: 1.0, blue: 0.55).opacity(isAccountPanelHovered ? 0.18 : 0.06),
                    Color(red: 0.48, green: 0.85, blue: 1.0).opacity(isAccountPanelHovered ? 0.14 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(isAccountPanelHovered ? 0.28 : 0.12), lineWidth: 1)
        )
    }

    private var supportedPlatformsCard: some View {
        LiquidHomeCard(accent: [Color(red: 0.70, green: 0.92, blue: 1.0), Color(red: 0.74, green: 1.0, blue: 0.58)]) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeader(
                        icon: "square.stack.3d.up.fill",
                        title: tr("Supported Platforms", "지원 플랫폼"),
                        subtitle: tr("KakaoTalk and Web Instagram work now. More everyday chat surfaces are planned.", "지금은 카카오톡과 Web Instagram을 지원하고, 앞으로 자주 쓰는 채팅 플랫폼을 더 추가할 예정입니다.")
                    )

                    Spacer(minLength: 0)

                    Text(tr("Live", "지원 중"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.68, green: 1.0, blue: 0.55), Color(red: 0.50, green: 0.90, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], alignment: .leading, spacing: 10) {
                    PlatformPill(
                        title: tr("KakaoTalk", "카카오톡"),
                        status: tr("Available now", "현재 지원"),
                        icon: "message.fill",
                        accent: [Color(red: 1.0, green: 0.86, blue: 0.22), Color(red: 0.70, green: 1.0, blue: 0.42)],
                        available: true
                    )
                    PlatformPill(
                        title: "Web Instagram",
                        status: tr("Available now", "현재 지원"),
                        icon: "globe",
                        accent: [Color(red: 0.58, green: 0.88, blue: 1.0), Color(red: 0.56, green: 1.0, blue: 0.78)],
                        available: true
                    )
                    PlatformPill(
                        title: "Slack",
                        status: tr("Coming soon", "추가 예정"),
                        icon: "number",
                        accent: [Color(red: 0.52, green: 0.86, blue: 1.0), Color(red: 0.92, green: 0.72, blue: 1.0)],
                        available: false
                    )
                    PlatformPill(
                        title: "Discord",
                        status: tr("Coming soon", "추가 예정"),
                        icon: "gamecontroller.fill",
                        accent: [Color(red: 0.66, green: 0.72, blue: 1.0), Color(red: 0.54, green: 0.94, blue: 1.0)],
                        available: false
                    )
                }

                Text(tr(
                    "Sayless is being built platform-by-platform so each app can feel native instead of generic.",
                    "Sayless는 플랫폼별로 자연스럽게 동작하도록 하나씩 확장하고 있습니다."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var styleSlotsCard: some View {
        LiquidHomeCard(accent: [Color(red: 0.78, green: 0.84, blue: 1.0), Color(red: 0.59, green: 1.0, blue: 0.75)]) {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(
                    icon: "slider.horizontal.3",
                    title: tr("Style Presets", "스타일 프리셋"),
                    subtitle: tr("Choose the three buttons that appear under generated replies.", "생성된 답변 아래에 표시될 세 개의 버튼을 고르세요.")
                )

                VStack(spacing: 10) {
                    ForEach(settings.slots) { slot in
                        StyleSlotRow(slot: slot)
                            .environmentObject(settings)
                    }
                }
            }
        }
    }

    private var personalStyleCard: some View {
        LiquidHomeCard(accent: [Color(red: 1.0, green: 0.79, blue: 0.48), Color(red: 0.63, green: 0.94, blue: 1.0)]) {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(
                    icon: "person.text.rectangle",
                    title: tr("Personal Customization", "개인 맞춤 설정"),
                    subtitle: tr("This local note is attached to every reply request.", "이 로컬 메모가 매 답변 요청에 함께 들어갑니다.")
                )

                VStack(alignment: .leading, spacing: 8) {
                    GrowingTextEditor(
                        text: $settings.personalInstruction,
                        placeholder: "예: 자주쓰는 말투\n할말 없을 때는 ㅋㅋ 치기\nOO 채팅방에서는 상대 킹받게 하기"
                    )

                    HStack {
                        Text("\(settings.personalInstruction.count)/\(ReplyStyleSettings.personalInstructionLimit)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(settings.personalInstruction.count >= ReplyStyleSettings.personalInstructionLimit ? .orange : .secondary)
                        Spacer()
                        if !settings.personalInstruction.isEmpty {
                            Button(tr("Clear", "지우기")) {
                                settings.personalInstruction = ""
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            HomeActionButton(
                title: tr("Preferences", "설정"),
                subtitle: appModel.summonShortcutTitle,
                icon: "gearshape.fill",
                accent: [Color(red: 0.66, green: 0.91, blue: 1.0), Color(red: 0.78, green: 1.0, blue: 0.65)]
            ) {
                navigation.selectedSection = .preferences
            }

            HomeActionButton(
                title: tr("Check Access", "권한 확인"),
                subtitle: appModel.accessibilityTrusted ? tr("Ready", "준비됨") : tr("Needs permission", "권한 필요"),
                icon: appModel.accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                accent: appModel.accessibilityTrusted
                    ? [Color(red: 0.68, green: 1.0, blue: 0.63), Color(red: 0.57, green: 0.86, blue: 0.78)]
                    : [Color(red: 1.0, green: 0.72, blue: 0.42), Color(red: 1.0, green: 0.54, blue: 0.64)]
            ) {
                appModel.openAccessibilitySettingsIfNeeded()
            }
        }
    }

    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: tr("Preferences", "설정"), subtitle: tr("Tune how Sayless appears, refreshes, and listens for shortcuts.", "Sayless의 표시 방식, 새로고침, 단축키를 조정하세요."))
            languageCard
            shortcutCard
            refreshShortcutCard
            iconCard
            updatesCard
            accessibilityCard
        }
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: tr("Guide", "가이드"), subtitle: tr("Open Sayless from the right place, then move through suggestions without breaking your flow.", "올바른 위치에서 Sayless를 열고 흐름을 끊지 않은 채 추천을 고르세요."))

            LiquidHomeCard(accent: [Color(red: 0.55, green: 0.95, blue: 0.72), Color(red: 0.46, green: 0.75, blue: 1.0)]) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "message.badge.waveform.fill", title: tr("How to summon Sayless", "Sayless 여는 법"), subtitle: tr("KakaoTalk or Web Instagram must be focused before the overlay opens.", "오버레이를 열기 전에 카카오톡 또는 Web Instagram이 활성화되어 있어야 합니다."))
                    GuideLine(number: 1, color: Color(red: 0.68, green: 1.0, blue: 0.54), title: tr("Open a KakaoTalk or Web Instagram chat", "카카오톡 또는 Web Instagram 채팅 열기"), detail: tr("Sayless reads the visible conversation from the active chat room.", "Sayless는 현재 채팅방에 보이는 대화를 읽습니다."))
                    GuideLine(number: 2, color: Color(red: 0.47, green: 0.86, blue: 1.0), title: tr("Click the message input", "메시지 입력창 클릭"), detail: tr("The text cursor must be inside the chat input before the overlay opens.", "오버레이를 열기 전에 커서가 채팅 입력창 안에 있어야 합니다."))
                    GuideLine(number: 3, color: Color(red: 0.92, green: 0.78, blue: 1.0), title: tr("Press \(appModel.summonShortcutTitle)", "\(appModel.summonShortcutTitle) 누르기"), detail: tr("Sayless appears near the input and prepares three replies.", "Sayless가 입력창 근처에 뜨고 답변 3개를 준비합니다."))
                }
            }

            LiquidHomeCard(accent: [Color(red: 1.0, green: 0.78, blue: 0.46), Color(red: 0.58, green: 1.0, blue: 0.78)]) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "text.bubble.fill", title: tr("Using replies", "답변 사용하기"), subtitle: tr("Keep the chat open and choose the line that fits best.", "채팅방을 열어둔 채 가장 어울리는 답변을 고르세요."))
                    GuideLine(number: 1, color: Color(red: 1.0, green: 0.73, blue: 0.42), title: tr("Pick a reply", "답변 고르기"), detail: tr("Click a card or move with Tab until the right response is selected.", "카드를 클릭하거나 Tab으로 이동해서 원하는 답변을 선택하세요."))
                    GuideLine(number: 2, color: Color(red: 0.57, green: 0.95, blue: 0.68), title: tr("Adjust the tone", "말투 조정하기"), detail: tr("Use the three Style Preset buttons under the cards to reshape the current replies.", "카드 아래 세 개의 스타일 버튼으로 현재 답변의 톤을 바꿀 수 있습니다."))
                    GuideLine(number: 3, color: Color(red: 0.60, green: 0.82, blue: 1.0), title: tr("Send when ready", "준비되면 보내기"), detail: tr("Press Enter to place the selected reply into the chat input.", "Enter를 누르면 선택한 답변이 채팅 입력창에 들어갑니다."))
                }
            }

            LiquidHomeCard(accent: [Color(red: 0.82, green: 0.78, blue: 1.0), Color(red: 0.56, green: 0.86, blue: 1.0)]) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "keyboard.fill", title: tr("All Shortcuts", "전체 단축키"), subtitle: tr("Every keyboard control currently handled by Sayless.", "현재 Sayless가 실제로 처리하는 모든 키보드 조작입니다."))
                    ShortcutLine(icon: "sparkles", color: Color(red: 0.68, green: 1.0, blue: 0.54), title: tr("Show or hide overlay", "오버레이 열기/숨기기"), value: appModel.summonShortcutTitle)
                    ShortcutLine(icon: "arrow.clockwise", color: Color(red: 0.50, green: 0.85, blue: 1.0), title: tr("Refresh replies", "답변 새로고침"), value: appModel.refreshShortcutTitle)
                    ShortcutLine(icon: "arrow.triangle.2.circlepath", color: Color(red: 0.50, green: 0.85, blue: 1.0), title: tr("Refresh replies", "답변 새로고침"), value: "⌘ R")
                    ShortcutLine(icon: "text.magnifyingglass", color: Color(red: 0.96, green: 0.74, blue: 1.0), title: tr("Reset context and regenerate", "문맥 다시 읽고 재생성"), value: "⌘ ⇧ R")
                    ShortcutLine(icon: "return", color: Color(red: 0.95, green: 0.76, blue: 1.0), title: tr("Accept selected item", "선택한 항목 적용"), value: "Enter")
                    ShortcutLine(icon: "return", color: Color(red: 0.74, green: 0.95, blue: 1.0), title: tr("Accept selected item", "선택한 항목 적용"), value: "Keypad Enter")
                    ShortcutLine(icon: "arrow.right", color: Color(red: 1.0, green: 0.75, blue: 0.45), title: tr("Next reply", "다음 답변"), value: "Tab")
                    ShortcutLine(icon: "arrow.left", color: Color(red: 0.68, green: 0.90, blue: 1.0), title: tr("Previous reply", "이전 답변"), value: "Shift Tab")
                    ShortcutLine(icon: "rectangle.stack.fill", color: Color(red: 0.67, green: 0.86, blue: 1.0), title: tr("Next batch", "다음 묶음"), value: "Control Tab")
                    ShortcutLine(icon: "rectangle.stack.fill", color: Color(red: 0.74, green: 0.78, blue: 1.0), title: tr("Previous batch", "이전 묶음"), value: "Control Shift Tab")
                    ShortcutLine(icon: "arrow.down", color: Color(red: 0.66, green: 1.0, blue: 0.72), title: tr("Move to adjustment bar", "스타일 버튼으로 이동"), value: "↓")
                    ShortcutLine(icon: "arrow.up", color: Color(red: 0.80, green: 1.0, blue: 0.62), title: tr("Return to replies", "답변 카드로 돌아가기"), value: "↑")
                    ShortcutLine(icon: "arrow.left.and.right", color: Color(red: 1.0, green: 0.82, blue: 0.46), title: tr("Choose adjustment", "스타일 버튼 이동"), value: "← / →")
                    ShortcutLine(icon: "text.cursor", color: Color(red: 0.62, green: 0.92, blue: 1.0), title: tr("Focus custom instruction", "커스텀 입력칸 포커스"), value: "↓")
                    ShortcutLine(icon: "escape", color: Color(red: 1.0, green: 0.60, blue: 0.66), title: tr("Close or cancel field", "닫기 또는 입력 취소"), value: "Esc")
                }
            }

            LiquidHomeCard(accent: [Color(red: 1.0, green: 0.64, blue: 0.72), Color(red: 0.72, green: 0.95, blue: 1.0)]) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "checkmark.shield.fill", title: tr("If it does not appear", "안 뜰 때 확인할 것"), subtitle: tr("Most issues come from focus or macOS Accessibility permission.", "대부분은 포커스나 macOS 손쉬운 사용 권한 문제입니다."))
                    GuideLine(number: 1, color: Color(red: 1.0, green: 0.62, blue: 0.68), title: tr("Check the active app", "활성 앱 확인"), detail: tr("Sayless reads the currently focused KakaoTalk or Web Instagram chat.", "Sayless는 현재 포커스된 카카오톡 또는 Web Instagram 채팅방을 읽습니다."))
                    GuideLine(number: 2, color: Color(red: 0.68, green: 1.0, blue: 0.62), title: tr("Check Accessibility", "손쉬운 사용 권한 확인"), detail: tr("Use Home > Preferences or the menu bar Check Accessibility action.", "홈 > 설정 또는 메뉴바의 권한 확인을 사용하세요."))
                    GuideLine(number: 3, color: Color(red: 0.66, green: 0.82, blue: 1.0), title: tr("Click the input again", "입력창 다시 클릭"), detail: tr("If the overlay opens in the wrong place, refocus the message input and summon Sayless again.", "오버레이 위치가 이상하면 입력창을 다시 클릭하고 Sayless를 다시 여세요."))
                }
            }
        }
    }

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: tr("Account", "계정"), subtitle: tr("Sign in, check plan usage, and manage your Sayless profile.", "로그인하고 사용량과 Sayless 프로필을 관리하세요."))

            if let configurationError = authSession.configurationError {
                NoticeCard(icon: "exclamationmark.triangle.fill", title: tr("Clerk is not configured", "Clerk 설정이 필요합니다"), message: configurationError, color: .orange)
            } else if clerk.user != nil {
                signedInAccountCard
                accountUsageCard
            } else {
                signedOutAccountCard
            }
        }
    }

    private var signedOutAccountCard: some View {
        LiquidHomeCard(accent: [Color(red: 0.48, green: 0.96, blue: 0.62), Color(red: 0.46, green: 0.76, blue: 0.95)]) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(icon: "person.badge.key.fill", title: tr("You are signed out", "로그아웃 상태"), subtitle: tr("Connect a Clerk account before using authenticated suggestions.", "인증된 추천을 사용하려면 계정을 연결하세요."))

                HStack(spacing: 10) {
                    Button(tr("Sign In", "로그인")) {
                        authSheetMode = .signIn
                    }
                    .buttonStyle(.borderedProminent)

                    Button(tr("Create Account", "계정 만들기")) {
                        authSheetMode = .signUp
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var signedInAccountCard: some View {
        LiquidHomeCard(accent: [Color(red: 0.68, green: 0.94, blue: 0.52), Color(red: 0.42, green: 0.85, blue: 0.69)]) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(icon: "checkmark.seal.fill", title: tr("Signed in", "로그인됨"), subtitle: authSession.userDisplayName)

                HStack(spacing: 10) {
                    Button(tr("Manage Profile", "프로필 관리")) {
                        isProfilePresented = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button(tr("Sign Out", "로그아웃")) {
                        authSession.signOut()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var accountUsageCard: some View {
        LiquidHomeCard(accent: [.mint, .cyan]) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeader(icon: "chart.bar.fill", title: tr("Plan & Usage", "플랜 및 사용량"), subtitle: tr("Local account status from the backend.", "백엔드에서 가져온 계정 상태입니다."))

                    Spacer(minLength: 0)

                    Button {
                        Task {
                            await accountStatus.load()
                        }
                    } label: {
                        Label(tr("Refresh Usage", "사용량 새로고침"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(accountStatus.isLoading)
                }

                if let account = accountStatus.account {
                    let dailyLimit = account.limits?.dailySuggestions ?? 100
                    let weeklyLimit = account.limits?.weeklySuggestions ?? 500

                    HStack(spacing: 12) {
                        UsageTile(title: tr("Plan", "플랜"), value: account.plan.capitalized, caption: account.subscription?.status ?? tr("No subscription", "구독 없음"))
                        UsageTile(title: tr("Today", "오늘"), value: "\(account.usage.daily.requests) / \(dailyLimit)", caption: tr("Daily requests", "일일 요청"))
                        UsageTile(title: tr("Week", "이번 주"), value: "\(account.usage.weekly.requests) / \(weeklyLimit)", caption: tr("Weekly requests", "주간 요청"))
                    }
                } else if let errorMessage = accountStatus.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text(tr("Usage will appear after your first authenticated request.", "인증된 요청을 처음 보낸 뒤 사용량이 표시됩니다."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var shortcutCard: some View {
        SettingsCard(title: tr("Shortcut", "단축키")) {
            Picker(tr("Shortcut", "단축키"), selection: $appModel.shortcutOption) {
                ForEach(ShortcutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if appModel.shortcutOption == .custom {
                ShortcutRecorderView(
                    title: "No custom shortcut",
                    subtitle: "Press Record, then use a modifier combo like Option S or Command Shift Space. Esc cancels.",
                    requiresModifier: true,
                    shortcut: $appModel.customShortcut
                )
            }
        }
    }

    private var refreshShortcutCard: some View {
        SettingsCard(title: tr("Refresh Context", "문맥 새로고침")) {
            Picker(tr("Refresh Context", "문맥 새로고침"), selection: $appModel.refreshShortcutOption) {
                ForEach(RefreshShortcutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if appModel.refreshShortcutOption == .custom {
                ShortcutRecorderView(
                    title: "No custom refresh shortcut",
                    subtitle: "Press Record, then choose a key for refreshing while the overlay is open. Esc cancels.",
                    requiresModifier: false,
                    shortcut: $appModel.customRefreshShortcut
                )
            }
        }
    }

    private var iconCard: some View {
        SettingsCard(title: tr("Menu Bar Icon", "메뉴바 아이콘")) {
            Picker(tr("Menu Bar Icon", "메뉴바 아이콘"), selection: $appModel.menuBarIconOption) {
                ForEach(MenuBarIconOption.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var updatesCard: some View {
        SettingsCard(title: tr("Updates", "업데이트")) {
            Toggle(
                tr("Automatically check for updates", "자동으로 업데이트 확인"),
                isOn: Binding(
                    get: { updateManager.automaticallyChecksForUpdates },
                    set: { updateManager.automaticallyChecksForUpdates = $0 }
                )
            )
            .toggleStyle(.switch)

            HStack {
                Text(tr("Version", "버전"))
                Spacer()
                Text(updateManager.appVersionDisplay)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .medium))

            Button(tr("Check for Updates...", "업데이트 확인...")) {
                updateManager.checkForUpdates()
            }
        }
    }

    private var accessibilityCard: some View {
        SettingsCard(title: tr("Accessibility", "손쉬운 사용")) {
            Label(
                appModel.accessibilityTrusted ? tr("Accessibility is enabled", "손쉬운 사용 권한이 켜져 있습니다") : tr("Accessibility is not enabled", "손쉬운 사용 권한이 꺼져 있습니다"),
                systemImage: appModel.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(appModel.accessibilityTrusted ? Color.green : Color.orange)

            Button(tr("Open Accessibility Settings", "손쉬운 사용 설정 열기")) {
                appModel.openAccessibilitySettingsIfNeeded()
            }
        }
    }

    private var languageCard: some View {
        SettingsCard(title: tr("Language", "언어")) {
            Picker(tr("App Language", "앱 언어"), selection: $languageSettings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(tr("Switches the Home, Preferences, Guide, Account, and menu bar UI language.", "홈, 설정, 가이드, 계정, 메뉴바 UI 언어가 바로 바뀝니다."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StyleSlotRow: View {
    let slot: ReplyStyleSlot
    @EnvironmentObject private var settings: ReplyStyleSettings
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @State private var isHovered = false

    var body: some View {
        let preset = settings.preset(for: slot)

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(isHovered ? 0.17 : 0.1))
                Image(systemName: preset.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.text("Button \(slot.id + 1)", "버튼 \(slot.id + 1)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(preset.title)
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer(minLength: 12)

            Picker("Button \(slot.id + 1)", selection: Binding(
                get: { slot.presetID },
                set: { settings.setPresetID($0, for: slot.id) }
            )) {
                ForEach(ReplyStyleSettings.availablePresets) { preset in
                    Label(preset.title, systemImage: preset.systemImage).tag(preset.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(12)
        .background(.white.opacity(isHovered ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct HomePanelBackground: View {
    let material: NSVisualEffectView.Material
    let tintOpacity: Double

    var body: some View {
        ZStack {
            VisualEffectView(
                material: material,
                blendingMode: .withinWindow,
                state: .followsWindowActiveState
            )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(tintOpacity))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 10)
    }
}

private struct HomeSidebarItem: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 17)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? .white.opacity(0.13) : .clear)
        )
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 23, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        LiquidHomeCard(accent: [Color(red: 0.70, green: 0.92, blue: 1.0), Color(red: 0.78, green: 1.0, blue: 0.68)]) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                content
            }
        }
    }
}

private struct GuideLine: View {
    let number: Int
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: [color.opacity(0.95), .white.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShortcutLine: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.28), lineWidth: 1)
                )
        }
    }
}

private struct PlatformPill: View {
    let title: String
    let status: String
    let icon: String
    let accent: [Color]
    let available: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: accent.map { $0.opacity(isHovered ? 0.96 : 0.76) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: (accent.last ?? .cyan).opacity(isHovered ? 0.35 : 0.14), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black.opacity(0.72))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text(status)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(available ? Color(red: 0.72, green: 1.0, blue: 0.62) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.105 : 0.058))

                LinearGradient(
                    colors: [
                        (accent.first ?? .mint).opacity(isHovered ? 0.18 : 0.07),
                        (accent.last ?? .cyan).opacity(isHovered ? 0.13 : 0.045),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                Capsule()
                    .fill(.white.opacity(isHovered ? 0.18 : 0.08))
                    .frame(width: 58, height: 6)
                    .blur(radius: 5)
                    .offset(x: 16, y: 8)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(isHovered ? 0.28 : 0.12), (accent.last ?? .cyan).opacity(isHovered ? 0.22 : 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovered ? 1.018 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.13 : 0.055), radius: isHovered ? 18 : 9, x: 0, y: isHovered ? 9 : 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.76), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct GrowingTextEditor: View {
    @Binding var text: String
    let placeholder: String

    private var editorHeight: CGFloat {
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        return min(92, max(46, CGFloat(lineCount) * 20 + 26))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.74))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: 14, weight: .medium))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: editorHeight, maxHeight: editorHeight)
        }
        .frame(minHeight: editorHeight, maxHeight: editorHeight)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: editorHeight)
    }
}

private struct NoticeCard: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        LiquidHomeCard(accent: [color.opacity(0.82), .orange.opacity(0.55)]) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UsageTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LiquidHomeCard<Content: View>: View {
    let accent: [Color]
    var reactsToHover = true
    @ViewBuilder let content: Content
    @State private var isHovered = false

    private var activeHover: Bool {
        reactsToHover && isHovered
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(activeHover ? 0.082 : 0.052))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    (accent.first ?? .mint).opacity(activeHover ? 0.13 : 0.06),
                                    (accent.last ?? .cyan).opacity(activeHover ? 0.09 : 0.035),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(activeHover ? 0.2 : 0.09), lineWidth: 1)
            )
            .scaleEffect(activeHover ? 1.008 : 1.0)
            .shadow(color: .black.opacity(activeHover ? 0.14 : 0.08), radius: activeHover ? 24 : 14, x: 0, y: activeHover ? 12 : 7)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: activeHover)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: [Color]
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: accent.map { $0.opacity(isHovered ? 0.95 : 0.78) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black.opacity(0.74))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.white.opacity(isHovered ? 0.082 : 0.052), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private enum HomeAuthSheetMode: String, Identifiable {
    case signIn
    case signUp

    var id: String {
        rawValue
    }

    var clerkMode: AuthView.Mode {
        switch self {
        case .signIn:
            return .signIn
        case .signUp:
            return .signUp
        }
    }
}
