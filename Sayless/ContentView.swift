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
                icon: "person.crop.circle",
                title: "Account",
                selected: selectedTab == .account
            ) {
                selectedTab = .account
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 70)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 140)
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
        case .account:
            accountContent
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

                HStack(alignment: .top, spacing: 12) {
                    UsageMetricCard(title: "Input tokens", value: formattedCount(account.usage.weekly.inputTokens), caption: "This week")
                    UsageMetricCard(title: "Output tokens", value: formattedCount(account.usage.weekly.outputTokens), caption: "This week")
                    UsageMetricCard(title: "Total", value: formattedCount(account.usage.weekly.totalTokens), caption: "Weekly tokens")
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.085), lineWidth: 1)
        )
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
}

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case account

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

private struct UsageMetricCard: View {
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
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.075), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
