import AppKit
import ApplicationServices
import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published var shortcutOption: ShortcutOption {
        didSet {
            UserDefaults.standard.set(shortcutOption.rawValue, forKey: Self.shortcutDefaultsKey)
            hotKeyManager?.configure(shortcutOption)
        }
    }
    @Published var menuBarIconOption: MenuBarIconOption {
        didSet {
            UserDefaults.standard.set(menuBarIconOption.rawValue, forKey: Self.menuBarIconDefaultsKey)
        }
    }

    private let accessibilityReader = AccessibilityReader()
    private let overlayController = OverlayPanelController()
    private let suggestionService = BackendSuggestionService()
    private var hotKeyManager: HotKeyManager?
    private var suggestionTask: Task<Void, Never>?
    private var lastSummonTime: CFAbsoluteTime = 0
    private static let shortcutDefaultsKey = "shortcutOption"
    private static let menuBarIconDefaultsKey = "menuBarIconOption"

    init() {
        let savedShortcut = UserDefaults.standard.string(forKey: Self.shortcutDefaultsKey)
        shortcutOption = savedShortcut.flatMap(ShortcutOption.init(rawValue:)) ?? .optionSpace
        let savedMenuBarIcon = UserDefaults.standard.string(forKey: Self.menuBarIconDefaultsKey)
        menuBarIconOption = savedMenuBarIcon.flatMap(MenuBarIconOption.init(rawValue:)) ?? .quoteBubble

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.handleSummon()
            }
        }
        hotKeyManager?.configure(shortcutOption)
    }

    func handleSummon() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSummonTime > 0.18 else {
            return
        }
        lastSummonTime = now

        accessibilityTrusted = accessibilityReader.isAccessibilityTrusted()

        if overlayController.isVisible {
            suggestionTask?.cancel()
            overlayController.hide()
            return
        }

        switch accessibilityReader.focusedKakaoTextContext() {
        case .ready(let context):
            let generation = overlayController.show(
                content: .generating(context: context),
                near: context.frame
            )
            suggestionTask?.cancel()
            suggestionTask = Task(priority: .utility) { [weak self] in
                await self?.loadSuggestions(for: context, generation: generation)
            }

        case .accessibilityMissing:
            overlayController.show(
                content: .notice(
                    title: "Allow Accessibility Access",
                    message: """
                    Sayless needs Accessibility permission to find the KakaoTalk message input.

                    Click Open System Settings, turn Sayless on in Privacy & Security > Accessibility, then quit and run Sayless again. If Sayless is already on, turn it off and on again, or remove it from the list and add the current build again.
                    """,
                    buttonTitle: "Open System Settings"
                ),
                near: nil
            )

        case .unsupportedApp:
            overlayController.hide()

        case .noTextFocus:
            overlayController.hide()

        case .noChatInput:
            overlayController.hide()
        }
    }

    private func loadSuggestions(for context: FocusedTextContext, generation: Int) async {
        await Task.yield()

        guard let window = context.windowElement else {
            return
        }

        let messages = accessibilityReader.collectVisibleKakaoMessages(in: window, limit: 20)
        guard !Task.isCancelled,
              !messages.isEmpty,
              accessibilityReader.isWindowUsable(window) else {
            return
        }

        do {
            let suggestions = try await suggestionService.suggestions(
                chatRoom: context.windowTitle,
                messages: messages
            )

            guard !Task.isCancelled else {
                return
            }

            overlayController.update(
                content: .suggestions(context: context, items: suggestions),
                for: generation
            )
        } catch {
            guard !Task.isCancelled else {
                return
            }

            overlayController.update(
                content: .generationFailed(context: context),
                for: generation
            )
            print("[Sayless][Backend] suggestions unavailable")
        }
    }

    func openAccessibilitySettingsIfNeeded() {
        accessibilityTrusted = accessibilityReader.requestAccessibilityIfNeeded()

        if !accessibilityTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkAccessibilityFromMenu() {
        accessibilityTrusted = accessibilityReader.isAccessibilityTrusted()

        if accessibilityTrusted {
            overlayController.showTemporary(
                content: .notice(
                    title: "Accessibility Enabled",
                    message: "Sayless already has permission to read the focused KakaoTalk input.",
                    buttonTitle: nil
                ),
                duration: 2.1
            )
        } else {
            openAccessibilitySettingsIfNeeded()
        }
    }
}
