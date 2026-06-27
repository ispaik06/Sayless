import AppKit
import ApplicationServices
import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published var shortcutOption: ShortcutOption {
        didSet {
            UserDefaults.standard.set(shortcutOption.rawValue, forKey: Self.shortcutDefaultsKey)
            hotKeyManager?.configure(shortcutOption, customShortcut: customShortcut)
        }
    }
    @Published var menuBarIconOption: MenuBarIconOption {
        didSet {
            UserDefaults.standard.set(menuBarIconOption.rawValue, forKey: Self.menuBarIconDefaultsKey)
        }
    }
    @Published var refreshShortcutOption: RefreshShortcutOption {
        didSet {
            UserDefaults.standard.set(refreshShortcutOption.rawValue, forKey: Self.refreshShortcutDefaultsKey)
            overlayController.configureRefreshShortcut(refreshShortcutOption, customShortcut: customRefreshShortcut)
        }
    }
    @Published var customShortcut: KeyboardShortcutSpec? {
        didSet {
            save(customShortcut, key: Self.customShortcutDefaultsKey)
            if shortcutOption == .custom {
                hotKeyManager?.configure(shortcutOption, customShortcut: customShortcut)
            }
        }
    }
    @Published var customRefreshShortcut: KeyboardShortcutSpec? {
        didSet {
            save(customRefreshShortcut, key: Self.customRefreshShortcutDefaultsKey)
            overlayController.configureRefreshShortcut(refreshShortcutOption, customShortcut: customRefreshShortcut)
        }
    }

    private let accessibilityReader = AccessibilityReader()
    private let overlayController = OverlayPanelController()
    private let suggestionService = BackendSuggestionService()
    private var hotKeyManager: HotKeyManager?
    private var preferencesWindowController: PreferencesWindowController?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionCache: SuggestionCache?
    private var lastSummonTime: CFAbsoluteTime = 0
    private static let shortcutDefaultsKey = "shortcutOption"
    private static let menuBarIconDefaultsKey = "menuBarIconOption"
    private static let refreshShortcutDefaultsKey = "refreshShortcutOption"
    private static let customShortcutDefaultsKey = "customShortcut"
    private static let customRefreshShortcutDefaultsKey = "customRefreshShortcut"

    init() {
        let savedShortcut = UserDefaults.standard.string(forKey: Self.shortcutDefaultsKey)
        shortcutOption = savedShortcut.flatMap(ShortcutOption.init(rawValue:)) ?? .optionSpace
        let savedMenuBarIcon = UserDefaults.standard.string(forKey: Self.menuBarIconDefaultsKey)
        menuBarIconOption = savedMenuBarIcon.flatMap(MenuBarIconOption.init(rawValue:)) ?? .quoteBubble
        let savedRefreshShortcut = UserDefaults.standard.string(forKey: Self.refreshShortcutDefaultsKey)
        refreshShortcutOption = savedRefreshShortcut.flatMap(RefreshShortcutOption.init(rawValue:)) ?? .commandR
        customShortcut = Self.loadShortcut(key: Self.customShortcutDefaultsKey)
        customRefreshShortcut = Self.loadShortcut(key: Self.customRefreshShortcutDefaultsKey)

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.handleSummon()
            }
        }
        hotKeyManager?.configure(shortcutOption, customShortcut: customShortcut)
        overlayController.configureRefreshShortcut(refreshShortcutOption, customShortcut: customRefreshShortcut)
        overlayController.onSuggestionGenerationRequested = { [weak self] context, intent in
            self?.generateSuggestions(for: context, intent: intent)
        }
        overlayController.onContextResetRequested = { [weak self] context in
            self?.resetAndRegenerateSuggestions(for: context)
        }
        overlayController.onSuggestionAccepted = { [weak self] in
            self?.suggestionTask?.cancel()
        }
        overlayController.onSourceWindowInvalidated = { [weak self] in
            self?.suggestionCache = nil
        }
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
            if let cached = cachedSuggestions(for: context) {
                suggestionTask?.cancel()
                overlayController.showSuggestions(
                    context: context,
                    batches: cached.batches,
                    near: context.frame
                )
                return
            }

            overlayController.resetSuggestionState()
            let generation = overlayController.show(
                content: .generating(context: context),
                near: context.frame
            )
            suggestionTask?.cancel()
            suggestionTask = Task(priority: .utility) { [weak self] in
                await self?.loadSuggestions(
                    for: context,
                    generation: generation,
                    intent: .initial,
                    previousSuggestions: [],
                    activeSuggestions: nil,
                    existingBatches: [],
                    forceRefresh: false
                )
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

    private func generateSuggestions(for context: FocusedTextContext, intent: SuggestionIntent) {
        suggestionTask?.cancel()
        let generation = overlayController.beginSuggestionRequest()
        let previousSuggestions = overlayController.suggestionHistory
        let activeSuggestions = activeSuggestionsForRequest(intent: intent)
        let existingBatches = overlayController.suggestionBatches
        suggestionTask = Task(priority: .utility) { [weak self] in
            await self?.loadSuggestions(
                for: context,
                generation: generation,
                intent: intent,
                previousSuggestions: previousSuggestions,
                activeSuggestions: activeSuggestions,
                existingBatches: existingBatches,
                forceRefresh: true
            )
        }
    }

    private func resetAndRegenerateSuggestions(for context: FocusedTextContext) {
        suggestionTask?.cancel()
        suggestionCache = nil
        overlayController.resetSuggestionState()
        let generation = overlayController.refresh(content: .generating(context: context))
        suggestionTask = Task(priority: .utility) { [weak self] in
            await self?.loadSuggestions(
                for: context,
                generation: generation,
                intent: .initial,
                previousSuggestions: [],
                activeSuggestions: nil,
                existingBatches: [],
                forceRefresh: true
            )
        }
    }

    private func loadSuggestions(
        for context: FocusedTextContext,
        generation: Int,
        intent: SuggestionIntent,
        previousSuggestions: [Suggestion],
        activeSuggestions: [Suggestion]?,
        existingBatches: [SuggestionBatch],
        forceRefresh: Bool
    ) async {
        await Task.yield()

        guard let window = context.windowElement else {
            finishUnavailableSuggestionRequest(context: context, generation: generation, existingBatches: existingBatches)
            return
        }

        let messages = accessibilityReader.collectVisibleKakaoMessages(in: window, limit: 20)
        guard !Task.isCancelled,
              !messages.isEmpty,
              accessibilityReader.isWindowUsable(window) else {
            finishUnavailableSuggestionRequest(context: context, generation: generation, existingBatches: existingBatches)
            return
        }
        let timelineSignature = accessibilityReader.latestVisibleKakaoMessageSignature(in: window)

        do {
            let draftText = currentDraftText(for: context)
            let suggestions = try await suggestionService.suggestions(
                chatRoom: context.windowTitle,
                messages: messages,
                draftText: draftText,
                intent: intent,
                previousSuggestions: previousSuggestions,
                activeSuggestions: activeSuggestions
            )

            guard !Task.isCancelled else {
                return
            }

            let batch = SuggestionBatch(intent: intent, suggestions: suggestions)
            let batches = existingBatches + [batch]
            suggestionCache = SuggestionCache(
                key: cacheKey(for: context),
                batches: batches,
                windowElement: context.windowElement,
                timelineSignature: timelineSignature,
                messages: messages,
                createdAt: Date()
            )

            overlayController.appendSuggestions(batch, context: context, for: generation)
        } catch {
            guard !Task.isCancelled else {
                return
            }

            if existingBatches.isEmpty {
                overlayController.update(
                    content: .generationFailed(context: context),
                    for: generation
                )
            } else {
                overlayController.finishSuggestionRequest()
            }
            print("[Sayless][Backend] suggestions unavailable\(forceRefresh ? " during refresh" : "")")
        }
    }

    private func currentDraftText(for context: FocusedTextContext) -> String? {
        let currentValue = accessibilityReader.textValue(of: context.element) ?? context.value
        let trimmedDraft = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDraft.isEmpty ? nil : trimmedDraft
    }

    private func activeSuggestionsForRequest(intent: SuggestionIntent) -> [Suggestion]? {
        switch intent {
        case .shorter, .softer, .wittier, .custom:
            let activeSuggestions = overlayController.activeSuggestions
            return activeSuggestions.count == 3 ? activeSuggestions : nil
        case .initial, .regenerate:
            return nil
        }
    }

    private func finishUnavailableSuggestionRequest(
        context: FocusedTextContext,
        generation: Int,
        existingBatches: [SuggestionBatch]
    ) {
        if existingBatches.isEmpty {
            overlayController.update(
                content: .generationFailed(context: context),
                for: generation
            )
        } else {
            overlayController.finishSuggestionRequest()
        }
    }

    private func cachedSuggestions(for context: FocusedTextContext) -> SuggestionCache? {
        guard let suggestionCache,
              suggestionCache.key == cacheKey(for: context) else {
            return nil
        }

        if let cachedWindow = suggestionCache.windowElement,
           !accessibilityReader.isWindowUsable(cachedWindow) {
            self.suggestionCache = nil
            overlayController.resetSuggestionState()
            return nil
        }

        if let cachedSignature = suggestionCache.timelineSignature,
           let window = context.windowElement,
           let currentSignature = accessibilityReader.latestVisibleKakaoMessageSignature(in: window),
           currentSignature.containsNewerMessages(than: cachedSignature) {
            self.suggestionCache = nil
            overlayController.resetSuggestionState()
            return nil
        }

        return suggestionCache
    }

    private func cacheKey(for context: FocusedTextContext) -> String {
        let title = context.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return "\(context.bundleIdentifier)|\(title)"
        }

        return "\(context.bundleIdentifier)|\(Int(context.frame.minX))|\(Int(context.frame.minY))"
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

    func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(appModel: self)
        }

        preferencesWindowController?.showPreferences()
    }

    private func save(_ shortcut: KeyboardShortcutSpec?, key: String) {
        if let shortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func loadShortcut(key: String) -> KeyboardShortcutSpec? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(KeyboardShortcutSpec.self, from: data)
    }
}

private struct SuggestionCache {
    let key: String
    let batches: [SuggestionBatch]
    let windowElement: AXUIElement?
    let timelineSignature: ChatTimelineSignature?
    let messages: [ChatMessage]
    let createdAt: Date
}
