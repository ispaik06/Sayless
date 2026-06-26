import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 590)
        .background(WindowAccessor { window in
            WindowStyling.applyPreferencesGlass(to: window)
        })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)

                Text("Sayless")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.bottom, 6)

            SidebarItem(icon: "keyboard", title: "Shortcut", selected: true)
            SidebarItem(icon: "menubar.rectangle", title: "Icon", selected: false)
            SidebarItem(icon: "lock.shield", title: "Privacy", selected: false)

            Spacer(minLength: 0)
        }
        .padding(.top, 44)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 140)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
        )
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
                accessibilityBlock

                Text("MVP test flow: open a KakaoTalk chat, click the message input, then press your summon shortcut.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.top, 44)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.05)
            }
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
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
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
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
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
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
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
