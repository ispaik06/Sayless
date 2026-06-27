import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var updateManager = UpdateManager.shared

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

            SidebarItem(icon: "keyboard", title: "Shortcut", selected: true)
            SidebarItem(icon: "menubar.rectangle", title: "Icon", selected: false)
            SidebarItem(icon: "arrow.triangle.2.circlepath", title: "Updates", selected: false)
            SidebarItem(icon: "lock.shield", title: "Privacy", selected: false)

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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preferences")
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
            .padding(.top, 24)
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PreferencesPanelBackground(material: .hudWindow, tintOpacity: 0.028))
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 17)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? .white.opacity(0.13) : .clear)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
