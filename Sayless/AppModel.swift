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
    private static let temporaryNoticeDuration: TimeInterval = 2.1

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

        if !accessibilityTrusted {
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
            return
        }

        switch accessibilityReader.fastFocusedKakaoTextContext() {
        case .ready(let context):
            showCachedSuggestionsOrStartLoading(for: context)

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

        case .noTextFocus, .noChatInput:
            overlayController.hide()
        }
    }

    private func showCachedSuggestionsOrStartLoading(for context: FocusedTextContext) {
        suggestionTask?.cancel()
        overlayController.resetSuggestionState()

        guard canRequestAuthenticatedSuggestions(near: context.frame) else {
            return
        }

        if let cached = cachedSuggestions(for: context, validateTimeline: false) {
            overlayController.showSuggestions(
                context: context,
                batches: cached.batches,
                near: context.frame
            )
            return
        }

        let generation = overlayController.show(
            content: .generating(context: context),
            near: context.frame
        )

        startInitialSuggestionLoad(for: context, generation: generation)
    }

    private func startInitialSuggestionLoad(for context: FocusedTextContext, generation: Int) {
        suggestionTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }

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
    }

    private func generateSuggestions(for context: FocusedTextContext, intent: SuggestionIntent) {
        suggestionTask?.cancel()
        guard canRequestAuthenticatedSuggestions(near: context.frame) else {
            return
        }

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
        guard canRequestAuthenticatedSuggestions(near: context.frame) else {
            return
        }

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

    private func canRequestAuthenticatedSuggestions(near frame: CGRect?) -> Bool {
        let authSession = AuthSessionManager.shared
        guard authSession.isSignedIn else {
            let message: String
            if authSession.configurationError != nil {
                message = "Sayless is still loading account configuration. Open Preferences > Account if this does not resolve."
            } else {
                message = "Open Preferences > Account and sign in before generating suggestions."
            }

            overlayController.showTemporary(
                content: .notice(
                    title: "Sign in required",
                    message: message,
                    buttonTitle: nil
                ),
                near: frame,
                duration: Self.temporaryNoticeDuration
            )
            return false
        }

        return true
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

        let messages = await collectVisibleMessages(in: window, limit: 20)
        guard !Task.isCancelled,
              !messages.isEmpty,
              accessibilityReader.isWindowUsable(window) else {
            finishUnavailableSuggestionRequest(context: context, generation: generation, existingBatches: existingBatches)
            return
        }
        let timelineSignature = accessibilityReader.latestVisibleKakaoMessageSignature(in: window)

        do {
            let draftText = draftTextForRequest(intent: intent, activeSuggestions: activeSuggestions, context: context)
            let participantCount = context.participantCount ?? accessibilityReader.participantCount(inChatWindow: window)
            let suggestions = try await suggestionService.suggestions(
                chatRoom: context.windowTitle,
                participantCount: participantCount,
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
                    content: .generationFailed(context: context, message: failureMessage(for: error)),
                    for: generation
                )
            } else {
                overlayController.finishSuggestionRequest()
            }
        }
    }

    private func currentDraftText(for context: FocusedTextContext) -> String? {
        let currentValue = accessibilityReader.textValue(of: context.element) ?? context.value
        let trimmedDraft = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDraft.isEmpty ? nil : trimmedDraft
    }

    private func draftTextForRequest(
        intent: SuggestionIntent,
        activeSuggestions: [Suggestion]?,
        context: FocusedTextContext
    ) -> String? {
        switch intent {
        case .shorter, .softer, .wittier:
            if activeSuggestions?.count == 3 {
                return nil
            }
        case .initial, .refresh(_), .regenerate, .custom:
            break
        }

        return currentDraftText(for: context)
    }

    private func collectVisibleMessages(in window: AXUIElement, limit: Int) async -> [ChatMessage] {
        let retryDelaysNanoseconds: [UInt64] = [0, 120_000_000, 280_000_000]

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled,
                  accessibilityReader.isWindowUsable(window) else {
                return []
            }

            let messages = accessibilityReader.collectVisibleKakaoMessages(in: window, limit: limit)
            if !messages.isEmpty {
                return messages
            }
        }

        return []
    }

    private func failureMessage(for error: Error) -> String? {
        let message = (error as? LocalizedError)?.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return message?.isEmpty == false ? message : nil
    }

    private func activeSuggestionsForRequest(intent: SuggestionIntent) -> [Suggestion]? {
        switch intent {
        case .shorter, .softer, .wittier, .custom:
            let activeSuggestions = overlayController.activeSuggestions
            return activeSuggestions.count == 3 ? activeSuggestions : nil
        case .initial, .refresh(_), .regenerate:
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
                content: .generationFailed(context: context, message: nil),
                for: generation
            )
        } else {
            overlayController.finishSuggestionRequest()
        }
    }

    private func cachedSuggestions(for context: FocusedTextContext, validateTimeline: Bool = true) -> SuggestionCache? {
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

        guard validateTimeline else {
            return suggestionCache
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
                duration: Self.temporaryNoticeDuration
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
