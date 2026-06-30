import AppKit
import ClerkKit
import ClerkKitUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var authSession: AuthSessionManager
    @Environment(Clerk.self) private var clerk
    @ObservedObject private var updateManager = UpdateManager.shared
    @StateObject private var accountStatus = AccountStatusService()
    @State private var selectedTab: PreferencesTab = .general
    @State private var authSheetMode: AuthSheetMode?
    @State private var isProfilePresented = false

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
                content
            }
            .padding(10)
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea()
        .frame(
            minWidth: 560,
            idealWidth: 640,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 590,
            maxHeight: .infinity
        )
        .clipShape(RoundedRectangle(cornerRadius: WindowStyling.preferencesCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WindowStyling.preferencesCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .background(WindowAccessor { window in
            WindowStyling.applyPreferencesGlass(to: window)
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
                    .shadow(color: .mint.opacity(0.35), radius: 5, x: 0, y: 1)

                Text("Sayless")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.bottom, 6)

            SidebarItem(
                icon: "slider.horizontal.3",
                title: "General",
                selected: selectedTab == .general
            ) {
                selectedTab = .general
            }

            SidebarItem(
                icon: "sparkles",
                title: "Guide",
                selected: selectedTab == .guide
            ) {
                selectedTab = .guide
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 70)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 150)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(PreferencesPanelBackground(material: .sidebar, tintOpacity: 0.035))
    }

    private var content: some View {
        ScrollView {
            selectedTabContent
                .padding(.top, 24)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PreferencesPanelBackground(material: .hudWindow, tintOpacity: 0.028))
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .guide:
            guideContent
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("General")
                    .font(.system(size: 23, weight: .bold))
                Text("Tune how Sayless appears, refreshes, and listens for shortcuts.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            shortcutCard
            refreshShortcutCard
            iconCard
            updatesCard
            accessibilityBlock

            Text("MVP test flow: open a KakaoTalk chat, click the message input, then press your summon shortcut.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            feedbackCard

            Spacer(minLength: 0)
        }
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Guide")
                    .font(.system(size: 23, weight: .bold))
                Text("Open Sayless from the right place, then move through suggestions without breaking your flow.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LiquidGuideCard(
                icon: "message.badge.waveform.fill",
                title: "How to summon Sayless",
                accent: [Color(red: 0.67, green: 0.92, blue: 1.0), Color(red: 0.58, green: 1.0, blue: 0.72)]
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    GuideStepRow(number: 1, title: "Open a KakaoTalk chat", detail: "Sayless reads the visible conversation from the active KakaoTalk chat room.")
                    GuideStepRow(number: 2, title: "Click the message input", detail: "The text cursor must be inside the chat input. If the cursor is not there, Sayless stays hidden.")
                    GuideStepRow(number: 3, title: "Press \(appModel.summonShortcutTitle)", detail: "The overlay appears near the chat input and starts preparing replies from the current context.")
                }
            }

            LiquidGuideCard(
                icon: "keyboard.fill",
                title: "Shortcuts",
                accent: [Color(red: 0.82, green: 0.78, blue: 1.0), Color(red: 0.56, green: 0.86, blue: 1.0)]
            ) {
                VStack(spacing: 10) {
                    ShortcutGuideRow(title: "Show or hide Sayless", value: appModel.summonShortcutTitle, detail: "Works globally after Sayless is running in the menu bar.")
                    ShortcutGuideRow(title: "Refresh suggestions", value: appModel.refreshShortcutTitle, detail: "Works while the Sayless overlay is open.")
                    ShortcutGuideRow(title: "Accept a suggestion", value: "Enter", detail: "Inserts the selected reply into the focused KakaoTalk input.")
                }
            }

            LiquidGuideCard(
                icon: appModel.accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                title: "If nothing opens",
                accent: appModel.accessibilityTrusted
                    ? [Color(red: 0.66, green: 1.0, blue: 0.68), Color(red: 0.55, green: 0.86, blue: 0.72)]
                    : [Color(red: 1.0, green: 0.78, blue: 0.46), Color(red: 1.0, green: 0.55, blue: 0.62)]
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    GuideCheckRow(text: "Make sure KakaoTalk is the frontmost app.")
                    GuideCheckRow(text: "Make sure a chat room is open, not just the chat list.")
                    GuideCheckRow(text: "Click inside the message input so the cursor is visible.")
                    GuideCheckRow(text: "Turn on Privacy & Security > Accessibility for Sayless.")

                    Button("Open Accessibility Settings") {
                        appModel.openAccessibilitySettingsIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
            }

            LiquidGuideCard(
                icon: "command",
                title: "All keyboard controls",
                accent: [Color(red: 0.72, green: 0.94, blue: 1.0), Color(red: 0.84, green: 1.0, blue: 0.58)]
            ) {
                VStack(spacing: 10) {
                    ShortcutGuideRow(title: "Show or hide overlay", value: appModel.summonShortcutTitle, detail: "Global shortcut from KakaoTalk when the chat input has focus.")
                    ShortcutGuideRow(title: "Next reply", value: "Tab", detail: "Moves keyboard selection through suggested replies.")
                    ShortcutGuideRow(title: "Previous reply", value: "Shift Tab", detail: "Moves keyboard selection backward through suggested replies.")
                    ShortcutGuideRow(title: "Next batch", value: "Control Tab", detail: "Switches to the next generated batch when multiple batches exist.")
                    ShortcutGuideRow(title: "Previous batch", value: "Control Shift Tab", detail: "Switches back to the previous generated batch.")
                    ShortcutGuideRow(title: "Accept selected item", value: "Enter", detail: "Accepts a reply, activates an adjustment, or submits a custom instruction.")
                    ShortcutGuideRow(title: "Refresh replies", value: "⌘ R", detail: "Requests another set of replies using the same visible context.")
                    ShortcutGuideRow(title: "Reset context", value: "⌘ ⇧ R", detail: "Rereads the KakaoTalk chat and regenerates from a fresh context.")
                    ShortcutGuideRow(title: "Move to adjustment bar", value: "↓", detail: "Moves focus from replies to tone/length adjustment controls.")
                    ShortcutGuideRow(title: "Return to replies", value: "↑", detail: "Moves focus back from adjustments to suggested replies.")
                    ShortcutGuideRow(title: "Choose adjustment", value: "← / →", detail: "Moves across adjustment buttons such as shorter, softer, or custom.")
                    ShortcutGuideRow(title: "Close or cancel field", value: "Esc", detail: "Closes Sayless, or exits the custom instruction field first.")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Account")
                    .font(.system(size: 23, weight: .bold))
                Text("Sign in to sync usage, unlock billing, and keep Sayless ready across sessions.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let configurationError = authSession.configurationError {
                accountConfigurationCard(message: configurationError)
            } else if clerk.user != nil {
                signedInAccountCard
                accountUsageCard
            } else {
                signedOutAccountCard
            }

            accountRoadmapCard

            Spacer(minLength: 0)
        }
    }

    private var signedOutAccountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.48, green: 0.96, blue: 0.62).opacity(0.9),
                                    Color(red: 0.46, green: 0.76, blue: 0.95).opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 52, height: 52)
                .shadow(color: .mint.opacity(0.24), radius: 14, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text("You are signed out")
                        .font(.system(size: 17, weight: .bold))
                    Text("Connect a Clerk account before using authenticated suggestions or managing a paid plan.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Sign in with Clerk") {
                    authSheetMode = .signIn
                }
                .buttonStyle(.borderedProminent)

                Button("Create account") {
                    authSheetMode = .signUp
                }
                .buttonStyle(.bordered)
            }

            Text("After sign-in, Sayless attaches your Clerk session token to backend requests automatically.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.058))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.mint.opacity(0.08), .cyan.opacity(0.04), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.095), lineWidth: 1)
        )
    }

    private var signedInAccountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.68, green: 0.94, blue: 0.52),
                                    Color(red: 0.42, green: 0.85, blue: 0.69)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 52, height: 52)
                .shadow(color: .green.opacity(0.22), radius: 14, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Signed in")
                        .font(.system(size: 17, weight: .bold))
                    Text(authSession.userDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Authenticated suggestions are enabled for this device.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Manage Profile") {
                    isProfilePresented = true
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Status") {
                    Task {
                        await accountStatus.load()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(accountStatus.isLoading)

                Button("Sign Out") {
                    authSession.signOut()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.058))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.08), .mint.opacity(0.04), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.095), lineWidth: 1)
        )
    }

    private var accountUsageCard: some View {
        HoverGlassCard(cornerRadius: 16, accent: [.mint, .cyan]) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Plan & Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if accountStatus.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }

                if let account = accountStatus.account {
                    let dailyLimit = account.limits?.dailySuggestions ?? 100
                    let weeklyLimit = account.limits?.weeklySuggestions ?? 500

                    HStack(alignment: .top, spacing: 12) {
                        UsageMetricCard(title: "Plan", value: account.plan.capitalized, caption: account.subscription?.status ?? "No subscription")
                        UsageMetricCard(title: "Today", value: "\(account.usage.daily.requests) / \(dailyLimit)", caption: "Daily requests")
                        UsageMetricCard(title: "Week", value: "\(account.usage.weekly.requests) / \(weeklyLimit)", caption: "Weekly requests")
                    }
                } else if let errorMessage = accountStatus.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Account usage will appear after your first authenticated request.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private var billingPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Free")
                        .font(.system(size: 16, weight: .bold))
                    Text("Stripe billing will connect here next.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Upgrade to Pro") {
                    // Stripe Checkout will replace this placeholder.
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private func accountConfigurationCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Clerk is not configured", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Set CLERK_PUBLISHABLE_KEY for the macOS build, or add ClerkPublishableKey to the app Info.plist.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private var accountRoadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming next")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            AccountRoadmapRow(icon: "speedometer", title: "Free plan limits", detail: "Block requests at 100/day or 500/week on the free plan.")
            AccountRoadmapRow(icon: "creditcard", title: "Billing", detail: "Open Stripe Checkout and manage Pro status.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Shortcut", selection: $appModel.shortcutOption) {
                ForEach(ShortcutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if appModel.shortcutOption == .custom {
                ShortcutRecorderView(
                    title: "No custom shortcut",
                    subtitle: "Press Record, then use a modifier combo like ⌥ S or ⌘ ⇧ Space. Esc cancels.",
                    requiresModifier: true,
                    shortcut: $appModel.customShortcut
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private var refreshShortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refresh Context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Refresh Context", selection: $appModel.refreshShortcutOption) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar Icon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Menu Bar Icon", selection: $appModel.menuBarIconOption) {
                ForEach(MenuBarIconOption.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Version")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(updateManager.appVersionDisplay)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updateManager.automaticallyChecksForUpdates },
                    set: { updateManager.automaticallyChecksForUpdates = $0 }
                )
            )
            .toggleStyle(.switch)

            HStack(spacing: 10) {
                Button("Check for Updates...") {
                    updateManager.checkForUpdates()
                }

                if !updateManager.canCheckForUpdates {
                    Text(updateManager.isUsingPlaceholderPublicKey ? "Public key placeholder" : "Updater busy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Sparkle installs updates in place and relaunches Sayless. The first install can still use a DMG; in-app updates use the ZIP archive from the public updates repo.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
    }

    private var accessibilityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                appModel.accessibilityTrusted ? "Accessibility is enabled" : "Accessibility is not enabled",
                systemImage: appModel.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(appModel.accessibilityTrusted ? .green : .orange)

            Button("Open Accessibility Settings") {
                appModel.openAccessibilitySettingsIfNeeded()
            }
        }
    }

    private var feedbackCard: some View {
        LiquidFeedbackButton(
            title: "Send Feedback",
            detail: "Tell us what felt useful, confusing, or missing.",
            icon: "paperplane.fill",
            accent: [Color(red: 0.66, green: 0.95, blue: 1.0), Color(red: 0.64, green: 1.0, blue: 0.68)]
        ) {
            openFeedbackEmail()
        }
    }

    private func openFeedbackEmail() {
        var components = URLComponents(string: "mailto:ispaik0602@gmail.com")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "Sayless Feedback"),
            URLQueryItem(
                name: "body",
                value: """
                Hi Sayless Team,

                I’d like to share some feedback about Sayless.

                Feedback type:
                Bug / Feature request / General feedback

                What happened or what would you like to see improved?

                App version: \(updateManager.appVersionDisplay)
                macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)

                Thanks!
                """
            )
        ]

        guard let url = components?.url else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case guide

    var id: String {
        rawValue
    }
}

private enum AuthSheetMode: String, Identifiable {
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

private struct PreferencesPanelBackground: View {
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

private struct SidebarItem: View {
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

private struct AccountRoadmapRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 18)

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

private struct LiquidGuideCard<Content: View>: View {
    let icon: String
    let title: String
    let accent: [Color]
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 42, height: 42)
                .shadow(color: accent.first?.opacity(isHovered ? 0.38 : 0.22) ?? .clear, radius: isHovered ? 18 : 12, x: 0, y: 6)

                Text(title)
                    .font(.system(size: 16, weight: .bold))

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.082 : 0.055))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (accent.first ?? .cyan).opacity(isHovered ? 0.12 : 0.07),
                                (accent.last ?? .mint).opacity(isHovered ? 0.08 : 0.035),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.18 : 0.09), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.018 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.14 : 0.08), radius: isHovered ? 24 : 14, x: 0, y: isHovered ? 12 : 7)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct LiquidFeedbackButton: View {
    let title: String
    let detail: String
    let icon: String
    let accent: [Color]
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: accent.map { $0.opacity(isHovered ? 0.98 : 0.78) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 44, height: 44)
                .shadow(color: accent.first?.opacity(isHovered ? 0.38 : 0.2) ?? .clear, radius: isHovered ? 18 : 12, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.74))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(isHovered ? 0.16 : 0.09), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
                    )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.086 : 0.056))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (accent.first ?? .cyan).opacity(isHovered ? 0.15 : 0.08),
                                (accent.last ?? .mint).opacity(isHovered ? 0.1 : 0.04),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.2 : 0.09), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.018 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.14 : 0.08), radius: isHovered ? 24 : 14, x: 0, y: isHovered ? 12 : 7)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct HoverGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let accent: [Color]
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.white.opacity(isHovered ? 0.082 : 0.052))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    (accent.first ?? .mint).opacity(isHovered ? 0.105 : 0.04),
                                    (accent.last ?? .cyan).opacity(isHovered ? 0.075 : 0.022),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(isHovered ? 0.18 : 0.085), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.012 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.13 : 0.08), radius: isHovered ? 22 : 12, x: 0, y: isHovered ? 11 : 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct GuideStepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.64), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ShortcutGuideRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private struct GuideCheckRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let caption: String
    @State private var isHovered = false

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
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.082 : 0.05))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .mint.opacity(isHovered ? 0.12 : 0.045),
                                .cyan.opacity(isHovered ? 0.08 : 0.025),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.18 : 0.075), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.025 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.13 : 0.06), radius: isHovered ? 18 : 8, x: 0, y: isHovered ? 9 : 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
