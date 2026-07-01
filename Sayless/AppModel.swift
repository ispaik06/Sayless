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
    @Published var customShortcut: KeyboardShortcutSpec? {
        didSet {
            save(customShortcut, key: Self.customShortcutDefaultsKey)
            if shortcutOption == .custom {
                hotKeyManager?.configure(shortcutOption, customShortcut: customShortcut)
            }
        }
    }

    private let accessibilityReader = AccessibilityReader()
    private let overlayController = OverlayPanelController()
    private let suggestionService = BackendSuggestionService()
    private var hotKeyManager: HotKeyManager?
    private var homeWindowController: HomeWindowController?
    private var styleSettingsCancellable: AnyCancellable?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionCache: SuggestionCache?
    private var lastSummonTime: CFAbsoluteTime = 0
    private static let shortcutDefaultsKey = "shortcutOption"
    private static let menuBarIconDefaultsKey = "menuBarIconOption"
    private static let customShortcutDefaultsKey = "customShortcut"
    private static let temporaryNoticeDuration: TimeInterval = 2.1

    init() {
        let savedShortcut = UserDefaults.standard.string(forKey: Self.shortcutDefaultsKey)
        shortcutOption = savedShortcut.flatMap(ShortcutOption.init(rawValue:)) ?? .optionSpace
        let savedMenuBarIcon = UserDefaults.standard.string(forKey: Self.menuBarIconDefaultsKey)
        menuBarIconOption = savedMenuBarIcon.flatMap(MenuBarIconOption.init(rawValue:)) ?? .quoteBubble
        customShortcut = Self.loadShortcut(key: Self.customShortcutDefaultsKey)

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.handleSummon()
            }
        }
        hotKeyManager?.configure(shortcutOption, customShortcut: customShortcut)
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
        styleSettingsCancellable = ReplyStyleSettings.shared.objectWillChange.sink { [weak self] _ in
            self?.suggestionCache = nil
        }
    }

    var summonShortcutTitle: String {
        if shortcutOption == .custom {
            return customShortcut?.title ?? "Custom"
        }

        return shortcutOption.title
    }

    var refreshShortcutTitle: String {
        "⌘ R"
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
                    title: tr("Allow Accessibility Access", "손쉬운 사용 권한을 허용해 주세요"),
                    message: tr(
                        """
                        Sayless needs Accessibility permission to find the KakaoTalk or Web Instagram message input.

                        Click Open System Settings, turn Sayless on in Privacy & Security > Accessibility, then quit and run Sayless again. If Sayless is already on, turn it off and on again, or remove it from the list and add the current build again.
                        """,
                        """
                        Sayless가 카카오톡 또는 Web Instagram 메시지 입력창을 찾으려면 손쉬운 사용 권한이 필요합니다.

                        시스템 설정 열기를 누른 뒤 개인정보 보호 및 보안 > 손쉬운 사용에서 Sayless를 켜고, Sayless를 종료한 다음 다시 실행해 주세요. 이미 켜져 있다면 껐다 켜거나 목록에서 제거한 뒤 현재 빌드를 다시 추가해 주세요.
                        """
                    ),
                    buttonTitle: tr("Open System Settings", "시스템 설정 열기")
                ),
                near: nil
            )
            return
        }

        guard canRequestAuthenticatedSuggestions(near: nil) else {
            return
        }

        switch accessibilityReader.focusedTextContext() {
        case .ready(let context):
            showCachedSuggestionsOrStartLoading(for: context)

        case .accessibilityMissing:
            overlayController.show(
                content: .notice(
                    title: tr("Allow Accessibility Access", "손쉬운 사용 권한을 허용해 주세요"),
                    message: tr(
                        """
                        Sayless needs Accessibility permission to find the KakaoTalk or Web Instagram message input.

                        Click Open System Settings, turn Sayless on in Privacy & Security > Accessibility, then quit and run Sayless again. If Sayless is already on, turn it off and on again, or remove it from the list and add the current build again.
                        """,
                        """
                        Sayless가 카카오톡 또는 Web Instagram 메시지 입력창을 찾으려면 손쉬운 사용 권한이 필요합니다.

                        시스템 설정 열기를 누른 뒤 개인정보 보호 및 보안 > 손쉬운 사용에서 Sayless를 켜고, Sayless를 종료한 다음 다시 실행해 주세요. 이미 켜져 있다면 껐다 켜거나 목록에서 제거한 뒤 현재 빌드를 다시 추가해 주세요.
                        """
                    ),
                    buttonTitle: tr("Open System Settings", "시스템 설정 열기")
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

        if canUseImmediateCache(for: context),
           let cached = cachedSuggestions(for: context, validateTimeline: false) {
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
            guard !Task.isCancelled else {
                return
            }

            await self?.loadSuggestions(
                for: context,
                generation: generation,
                intent: .initial,
                previousSuggestions: [],
                activeSuggestions: nil,
                existingBatches: []
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
                existingBatches: existingBatches
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
                existingBatches: []
            )
        }
    }

    private func canRequestAuthenticatedSuggestions(near frame: CGRect?) -> Bool {
        let authSession = AuthSessionManager.shared
        guard authSession.isSignedIn else {
            let message: String
            if authSession.configurationError != nil {
                message = tr(
                    "Sayless is still loading account configuration. Open Preferences > Account if this does not resolve.",
                    "Sayless가 아직 계정 설정을 불러오는 중입니다. 계속 해결되지 않으면 설정 > 계정을 열어 확인해 주세요."
                )
            } else {
                message = tr(
                    "Open Preferences > Account and sign in before generating suggestions.",
                    "추천을 생성하기 전에 설정 > 계정에서 로그인해 주세요."
                )
            }

            overlayController.showTemporary(
                content: .notice(
                    title: tr("Sign in required", "로그인이 필요합니다"),
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
        existingBatches: [SuggestionBatch]
    ) async {
        await Task.yield()

        guard let window = context.windowElement else {
            finishUnavailableSuggestionRequest(context: context, generation: generation, existingBatches: existingBatches)
            return
        }

        let visibleSnapshot = await visibleSnapshotForRequest(context: context, intent: intent, limit: 20)
        let requestContext = contextWithVisibleSnapshot(visibleSnapshot, from: context)
        let messages = visibleSnapshot.messages
        guard !Task.isCancelled,
              !messages.isEmpty,
              accessibilityReader.isWindowUsable(window) else {
            finishUnavailableSuggestionRequest(context: context, generation: generation, existingBatches: existingBatches)
            return
        }
        let timelineSignature = accessibilityReader.timelineSignature(from: messages)

        do {
            let draftText = draftTextForRequest(intent: intent, activeSuggestions: activeSuggestions, context: requestContext)
            let participantCount: Int?
            switch requestContext.source {
            case .kakaoTalk:
                participantCount = requestContext.participantCount ?? accessibilityReader.participantCount(inChatWindow: window)
            case .webInstagram:
                participantCount = requestContext.participantCount
            }
            let suggestions = try await suggestionService.suggestions(
                chatRoom: requestContext.windowTitle,
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
                key: cacheKey(for: requestContext),
                batches: batches,
                windowElement: requestContext.windowElement,
                timelineSignature: timelineSignature,
                messages: messages,
                createdAt: Date()
            )

            overlayController.appendSuggestions(batch, context: requestContext, for: generation)
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
        case .shorter, .softer, .wittier, .custom:
            if activeSuggestions?.count == 3 {
                return nil
            }
        case .initial, .refresh(_), .regenerate:
            break
        }

        return currentDraftText(for: context)
    }

    private func collectVisibleMessages(for context: FocusedTextContext, limit: Int) async -> [ChatMessage] {
        let retryDelaysNanoseconds: [UInt64] = [0, 120_000_000, 280_000_000]

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled,
                  let window = context.windowElement,
                  accessibilityReader.isWindowUsable(window) else {
                return []
            }

            let messages = accessibilityReader.collectVisibleMessages(for: context, limit: limit)
            if !messages.isEmpty {
                return messages
            }
        }

        return []
    }

    private func messagesForRequest(
        context: FocusedTextContext,
        intent: SuggestionIntent,
        limit: Int
    ) async -> [ChatMessage] {
        if intent == .initial,
           !context.chatMessages.isEmpty {
            return Array(context.chatMessages.suffix(limit))
        }

        return await collectVisibleMessages(for: context, limit: limit)
    }

    private func visibleSnapshotForRequest(
        context: FocusedTextContext,
        intent: SuggestionIntent,
        limit: Int
    ) async -> VisibleChatSnapshot {
        if intent == .initial,
           !context.chatMessages.isEmpty {
            return VisibleChatSnapshot(
                title: context.windowTitle,
                messages: Array(context.chatMessages.suffix(limit))
            )
        }

        let retryDelaysNanoseconds: [UInt64] = [0, 120_000_000, 280_000_000]
        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled,
                  let window = context.windowElement,
                  accessibilityReader.isWindowUsable(window) else {
                return VisibleChatSnapshot(title: context.windowTitle, messages: [])
            }

            let snapshot = accessibilityReader.collectVisibleChatSnapshot(for: context, limit: limit)
            if !snapshot.messages.isEmpty {
                return snapshot
            }
        }

        return VisibleChatSnapshot(title: context.windowTitle, messages: [])
    }

    private func contextWithVisibleSnapshot(
        _ snapshot: VisibleChatSnapshot,
        from context: FocusedTextContext
    ) -> FocusedTextContext {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return FocusedTextContext(
            source: context.source,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            element: context.element,
            windowElement: context.windowElement,
            windowTitle: title.isEmpty ? context.windowTitle : title,
            participantCount: context.participantCount,
            role: context.role,
            value: context.value,
            frame: context.frame,
            windowFrame: context.windowFrame,
            chatMessages: snapshot.messages
        )
    }

    private func canUseImmediateCache(for context: FocusedTextContext) -> Bool {
        if context.source == .webInstagram,
           context.chatMessages.isEmpty {
            return false
        }

        return true
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
           let currentSignature = accessibilityReader.latestVisibleMessageSignature(for: context),
           currentSignature.containsNewerMessages(than: cachedSignature) {
            self.suggestionCache = nil
            overlayController.resetSuggestionState()
            return nil
        }

        return suggestionCache
    }

    private func cacheKey(for context: FocusedTextContext) -> String {
        if context.source == .webInstagram {
            if let signature = accessibilityReader.timelineSignature(from: context.chatMessages) {
                return instagramCacheKey(context: context, signature: signature)
            }

            let title = context.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(context.bundleIdentifier)|instagram|\(title)|\(Int(context.frame.minX))|\(Int(context.frame.minY))"
        }

        let title = context.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return "\(context.bundleIdentifier)|\(title)"
        }

        return "\(context.bundleIdentifier)|\(Int(context.frame.minX))|\(Int(context.frame.minY))"
    }

    private func instagramCacheKey(context: FocusedTextContext, signature: ChatTimelineSignature) -> String {
        let signatureKey = signature.tail
            .map { fingerprint in
                [
                    fingerprint.role,
                    fingerprint.senderHash.map(String.init) ?? "-",
                    String(fingerprint.textHash)
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        return "\(context.bundleIdentifier)|instagram|\(signatureKey)"
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
                    title: tr("Accessibility Enabled", "손쉬운 사용 권한 켜짐"),
                    message: tr(
                        "Sayless already has permission to read the focused KakaoTalk or Web Instagram input.",
                        "Sayless가 이미 카카오톡 또는 Web Instagram 입력창을 읽을 수 있는 권한을 가지고 있습니다."
                    ),
                    buttonTitle: nil
                ),
                duration: Self.temporaryNoticeDuration
            )
        } else {
            openAccessibilitySettingsIfNeeded()
        }
    }

    func openPreferences() {
        openHome(section: .preferences)
    }

    private func tr(_ english: String, _ korean: String) -> String {
        AppLanguageSettings.shared.text(english, korean)
    }

    func openHome(section: HomeSection = .home) {
        if homeWindowController == nil {
            homeWindowController = HomeWindowController(appModel: self)
        }

        homeWindowController?.showHome(section: section)
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
