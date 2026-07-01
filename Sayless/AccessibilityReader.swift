import AppKit
import ApplicationServices

struct FocusedTextContext {
    let source: ChatContextSource
    let appName: String
    let bundleIdentifier: String
    let element: AXUIElement
    let windowElement: AXUIElement?
    let windowTitle: String
    let participantCount: Int?
    let role: String
    let value: String
    let frame: CGRect
    let windowFrame: CGRect?
    let chatMessages: [ChatMessage]
}

enum ChatContextSource {
    case kakaoTalk
    case webInstagram
}

private enum BrowserKind: String {
    case chrome
    case safari
    case unknown
}

struct ChatMessage {
    let sender: String
    let text: String
    let frame: CGRect
    let debugSource: String?
}

struct ChatTimelineSignature: Equatable {
    let tail: [ChatMessageFingerprint]

    func hasMeaningfulOverlap(with other: ChatTimelineSignature, minimum: Int = 2) -> Bool {
        let requiredOverlap = min(minimum, tail.count, other.tail.count)
        guard requiredOverlap > 0 else {
            return false
        }

        for overlap in stride(from: min(tail.count, other.tail.count), through: requiredOverlap, by: -1) {
            if Array(tail.suffix(overlap)) == Array(other.tail.prefix(overlap))
                || Array(other.tail.suffix(overlap)) == Array(tail.prefix(overlap)) {
                return true
            }
        }

        return false
    }

    func containsNewerMessages(than previous: ChatTimelineSignature) -> Bool {
        guard tail != previous.tail,
              !tail.isEmpty,
              !previous.tail.isEmpty else {
            return false
        }

        let maxOverlap = min(previous.tail.count, tail.count)
        let minimumOverlap = min(2, maxOverlap)
        guard minimumOverlap > 0 else {
            return false
        }

        for overlap in stride(from: maxOverlap, through: minimumOverlap, by: -1) {
            if Array(previous.tail.suffix(overlap)) == Array(tail.prefix(overlap)) {
                return tail.count > overlap
            }
        }

        return false
    }
}

struct ChatMessageFingerprint: Equatable {
    let role: String
    let senderHash: Int?
    let textHash: Int
}

private struct MessageTextCandidate {
    let text: String
    let frame: CGRect
}

private struct RowScanResult {
    let messageCandidates: [MessageTextCandidate]
    let senderCandidates: [(text: String, frame: CGRect)]
    let hasSystemFeedMarker: Bool
}

private struct VisibleRowsResult {
    let rows: [AXUIElement]
    let source: String
}

private struct ChatRoomMetadata {
    let title: String
    let participantCount: Int?
}

private struct AXElementSnapshot {
    let role: String
    let subrole: String?
    let value: String?
    let title: String?
    let description: String?
    let help: String?
    let label: String?
    let placeholder: String?
    let identifier: String?
    let roleDescription: String?
    let frame: CGRect?
    let isFocused: Bool?
    let isEnabled: Bool?
    let isEditable: Bool
    let children: [AXUIElement]
}

private struct InstagramTextCandidate {
    let text: String
    let role: String
    let frame: CGRect
    let parentChain: [InstagramAncestorSnapshot]
    let depth: Int
}

private struct InstagramAncestorSnapshot {
    let role: String
    let value: String?
    let title: String?
    let description: String?
    let help: String?
}

private struct InstagramInputCandidate {
    let element: AXUIElement
    let frame: CGRect
    let role: String
    let placeholder: String?
    let identity: String
    let parentDescription: String?
    let ancestorChain: String
    let hasTextEntryAreaAncestor: Bool
    let hasBrowserAccessibilityAncestor: Bool
    let keyboardFocused: Bool?
    let score: Int
}

private struct InstagramInputAncestorInfo {
    let identity: String
    let parentDescription: String?
    let ancestorChain: String
    let hasTextEntryArea: Bool
    let hasBrowserAccessibility: Bool
    let textEntryElement: AXUIElement?
}

private struct InstagramReplyInfo {
    let description: String?
    let quotedText: String?
}

private struct InstagramChatSnapshot {
    let browserKind: BrowserKind
    let chatTitle: String?
    let activeStatus: String?
    let messages: [ChatMessage]
    let inputField: AXUIElement?
}

private enum ParsedChatRow {
    case system(text: String, frame: CGRect)
    case message(ChatMessage)

    var message: ChatMessage? {
        if case let .message(message) = self {
            return message
        }

        return nil
    }
}

enum SummonResult {
    case ready(FocusedTextContext)
    case accessibilityMissing
    case unsupportedApp
    case noTextFocus
    case noChatInput
}

final class AccessibilityReader {
    private let incomingMessageXOffset: CGFloat = 60
    private let incomingMessageXTolerance: CGFloat = 22
    private let senderNameXTolerance: CGFloat = 28
    private typealias AXElementID = UInt
    private var cachedChatTable: AXUIElement?
    private var cachedChatWindowID: AXElementID?

    func focusedTextContext(includeParticipantCount: Bool = true) -> SummonResult {
        guard isAccessibilityTrusted() else {
            return .accessibilityMissing
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .unsupportedApp
        }

        if isBrowser(app) {
            let instagramResult = focusedWebInstagramTextContext(app: app)
            if case .ready = instagramResult {
                return instagramResult
            }
        }

        if isKakaoTalk(app) {
            return fastFocusedKakaoTextContext()
        }

        return .unsupportedApp
    }

    func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func focusedKakaoTextContext(includeParticipantCount: Bool = true) -> SummonResult {
        guard isAccessibilityTrusted() else {
            return .accessibilityMissing
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              isKakaoTalk(app) else {
            return .unsupportedApp
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let input = findFocusedKakaoChatInput(in: appElement) else {
            return .noChatInput
        }

        focus(input)
        return context(for: input, app: app, includeParticipantCount: includeParticipantCount)
    }

    func fastFocusedKakaoTextContext() -> SummonResult {
        guard isAccessibilityTrusted() else {
            return .accessibilityMissing
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              isKakaoTalk(app) else {
            return .unsupportedApp
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = copyAttribute(appElement, kAXFocusedUIElementAttribute) as AXUIElement? else {
            return .noTextFocus
        }

        var input: AXUIElement?
        if isKakaoChatInput(focusedElement) {
            input = focusedElement
        } else {
            input = inputAncestor(of: focusedElement)
        }

        if input == nil,
           let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement? {
            input = bestInput(from: chatInputs(in: focusedWindow, maxVisited: 140))
        }

        guard let input else {
            return .noChatInput
        }

        focus(input)
        return context(for: input, app: app, includeParticipantCount: false)
    }

    func collectVisibleMessages(for context: FocusedTextContext, limit: Int = 20) -> [ChatMessage] {
        guard let window = context.windowElement else {
            return []
        }

        switch context.source {
        case .kakaoTalk:
            return collectVisibleKakaoMessages(in: window, limit: limit)
        case .webInstagram:
            return collectVisibleInstagramMessages(in: window, limit: limit)
        }
    }

    func latestVisibleMessageSignature(for context: FocusedTextContext) -> ChatTimelineSignature? {
        guard let window = context.windowElement else {
            return nil
        }

        switch context.source {
        case .kakaoTalk:
            return latestVisibleKakaoMessageSignature(in: window)
        case .webInstagram:
            let messages = collectVisibleInstagramMessages(in: window, limit: 10, logExtraction: false)
            let tail = messages.suffix(8).map { message in
                ChatMessageFingerprint(
                    role: message.sender == "Me" ? "me" : "other",
                    senderHash: message.sender == "Me" ? nil : stableHash(message.sender),
                    textHash: stableHash(message.text)
                )
            }
            return tail.isEmpty ? nil : ChatTimelineSignature(tail: Array(tail))
        }
    }

    func timelineSignature(from messages: [ChatMessage]) -> ChatTimelineSignature? {
        let tail = messages.suffix(8).map { message in
            ChatMessageFingerprint(
                role: message.sender == "Me" ? "me" : "other",
                senderHash: message.sender == "Me" ? nil : stableHash(message.sender),
                textHash: stableHash(message.text)
            )
        }

        return tail.isEmpty ? nil : ChatTimelineSignature(tail: Array(tail))
    }

    func focusInput(for context: FocusedTextContext) -> Bool {
        switch context.source {
        case .kakaoTalk:
            focus(context.element)
            return true
        case .webInstagram:
            guard let window = context.windowElement else {
                return focusElementAndVerify(context.element, appPID: nil)
            }

            return focusInstagramInput(in: window, appPID: nil, fallbackElement: context.element)
        }
    }

    func insertionElement(for context: FocusedTextContext) -> AXUIElement? {
        switch context.source {
        case .kakaoTalk:
            return context.element
        case .webInstagram:
            guard let window = context.windowElement else {
                instagramAXLog("pre-insert validation failed: missing Instagram window")
                return nil
            }

            let browserKind = browserKind(appName: context.appName, bundleIdentifier: context.bundleIdentifier)
            let sortedCandidates = instagramInputCandidates(in: window, browserKind: browserKind).sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                if abs(lhs.frame.minY - rhs.frame.minY) > 8 {
                    return lhs.frame.minY > rhs.frame.minY
                }

                return lhs.frame.width > rhs.frame.width
            }

            for candidate in sortedCandidates {
                if validateInstagramInsertionTarget(candidate.element, window: window, browserKind: browserKind, logPrefix: "pre-insert candidate validation") {
                    instagramAXLog("pre-insert selected target: role=\(candidate.role) score=\(candidate.score) frame=\(frameText(candidate.frame)) ancestors=\(candidate.ancestorChain)")
                    return candidate.element
                }
            }

            if validateInstagramInsertionTarget(context.element, window: window, browserKind: browserKind, logPrefix: "pre-insert context validation") {
                instagramAXLog("pre-insert selected existing context target: \(compactElementDescription(context.element))")
                return context.element
            }

            instagramAXLog("pre-insert validation failed: no safe Instagram DM composer target; refusing fallback insertion")
            return nil
        }
    }

    func setValue(_ text: String, into element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    func textValue(of element: AXUIElement) -> String? {
        copyStringAttribute(element, kAXValueAttribute as String)
    }

    func collectVisibleKakaoMessages(limit: Int = 20) -> [ChatMessage] {
        guard isAccessibilityTrusted() else {
            return []
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              isKakaoTalk(app) else {
            return []
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement? else {
            return []
        }

        return collectVisibleKakaoMessages(in: focusedWindow, limit: limit)
    }

    func collectVisibleKakaoMessages(in focusedWindow: AXUIElement, limit: Int = 20) -> [ChatMessage] {
        guard isAccessibilityTrusted() else {
            return []
        }

        guard isWindowUsable(focusedWindow) else {
            return []
        }

        guard let chatTable = findChatTable(in: focusedWindow) else {
            return []
        }

        let tableFrame = frame(of: chatTable)
        var visibleRowsResult = visibleRows(in: chatTable)
        if visibleRowsResult.rows.isEmpty {
            invalidateCachedChatTable()
            if let refreshedTable = findChatTable(in: focusedWindow) {
                visibleRowsResult = visibleRows(in: refreshedTable)
            }
        }

        let parseLimit = min(limit + 4, 28)
        let rows = Array(visibleRowsResult.rows.suffix(parseLimit))
        var parsedRows: [ParsedChatRow] = []
        var inheritedSender = "Unknown"

        for (index, row) in rows.enumerated() {
            if index % 4 == 0,
               !isWindowUsable(focusedWindow) {
                return []
            }

            let rowScan = scanRowOnce(row)
            let messageCandidates = rowScan.messageCandidates
            guard !messageCandidates.isEmpty else { continue }

            let text = messageCandidates.map(\.text).joined(separator: "\n")
            let messageFrame = unionFrame(messageCandidates.map(\.frame))

            if rowScan.hasSystemFeedMarker {
                parsedRows.append(.system(text: text, frame: unionFrame(messageCandidates.map(\.frame))))
                continue
            }

            let isMine = isOutgoingMessage(messageCandidates, tableFrame: tableFrame, row: row)
            let explicitSender = isMine ? nil : senderCandidate(from: rowScan, messageFrame: messageFrame, tableFrame: tableFrame)
            if let explicitSender {
                inheritedSender = explicitSender
            }

            let sender = isMine ? "Me" : inheritedSender

            parsedRows.append(
                .message(
                    ChatMessage(
                        sender: sender,
                        text: text,
                        frame: messageFrame,
                        debugSource: nil
                    )
                )
            )
        }

        let finalRows = trimParsedRows(parsedRows, messageLimit: limit)
        return finalRows.compactMap(\.message)
    }

    func latestVisibleKakaoMessageSignature(in focusedWindow: AXUIElement) -> ChatTimelineSignature? {
        guard isAccessibilityTrusted(),
              isWindowUsable(focusedWindow),
              let chatTable = findChatTable(in: focusedWindow) else {
            return nil
        }

        let tableFrame = frame(of: chatTable)
        let visibleRowsResult = visibleRows(in: chatTable)
        let allRows = rows(from: chatTable)
        let canUseAllRows = allRows.count > visibleRowsResult.rows.count
        if !canUseAllRows,
           isChatTableScrolledToBottom(chatTable) != true {
            return nil
        }

        let timelineRows = canUseAllRows ? allRows : visibleRowsResult.rows
        let rows = Array(timelineRows.suffix(10))
        var inheritedSender = "Unknown"
        var fingerprints: [ChatMessageFingerprint] = []

        for row in rows {
            let rowScan = scanRowOnce(row)
            guard !rowScan.messageCandidates.isEmpty,
                  !rowScan.hasSystemFeedMarker else {
                continue
            }

            let text = rowScan.messageCandidates.map(\.text).joined(separator: "\n")
            let messageFrame = unionFrame(rowScan.messageCandidates.map(\.frame))
            let isMine = isOutgoingMessage(rowScan.messageCandidates, tableFrame: tableFrame, row: row)
            let explicitSender = isMine ? nil : senderCandidate(from: rowScan, messageFrame: messageFrame, tableFrame: tableFrame)
            if let explicitSender {
                inheritedSender = explicitSender
            }

            fingerprints.append(
                ChatMessageFingerprint(
                    role: isMine ? "me" : "other",
                    senderHash: isMine ? nil : stableHash(inheritedSender),
                    textHash: stableHash(text)
                )
            )
        }

        let tail = Array(fingerprints.suffix(8))
        return tail.isEmpty ? nil : ChatTimelineSignature(tail: tail)
    }

    func isWindowUsable(_ window: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
        guard roleResult == .success,
              (roleValue as? String) == kAXWindowRole as String else {
            return false
        }

        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
           let minimized = minimizedValue as? Bool,
           minimized {
            return false
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success
            && AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
    }

    private func isKakaoTalk(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        return name.contains("kakaotalk") || name.contains("kakao") || bundleID.contains("kakao")
    }

    private func isBrowser(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        let browserTokens = [
            "safari",
            "chrome",
            "chromium",
            "arc",
            "atlas",
            "browser",
            "edge",
            "firefox",
            "brave"
        ]

        return browserTokens.contains { name.contains($0) || bundleID.contains($0) }
    }

    private func browserKind(for app: NSRunningApplication) -> BrowserKind {
        browserKind(appName: app.localizedName ?? "", bundleIdentifier: app.bundleIdentifier ?? "")
    }

    private func browserKind(appName: String, bundleIdentifier: String) -> BrowserKind {
        let name = appName.lowercased()
        let bundleID = bundleIdentifier.lowercased()

        if bundleID == "com.google.chrome" || name.contains("chrome") || bundleID.contains("chromium") {
            return .chrome
        }

        if bundleID == "com.apple.safari" || name.contains("safari") {
            return .safari
        }

        return .unknown
    }

    private func focusedWebInstagramTextContext(app: NSRunningApplication) -> SummonResult {
        let browserKind = browserKind(for: app)
        instagramAXLog("detected browser kind: \(browserKind.rawValue)")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement?,
              isWindowUsable(focusedWindow) else {
            instagramAXLog("Instagram window found: false")
            return .unsupportedApp
        }

        let windowTitle = chatRoomTitle(for: focusedWindow)
        let lowerWindowTitle = windowTitle.lowercased()
        let titleMentionsInstagram = lowerWindowTitle.contains("instagram")

        if titleMentionsInstagram,
           let fastInput = fastFocusedInstagramInput(in: focusedWindow, appElement: appElement, browserKind: browserKind) {
            instagramAXLog("Instagram window found: true title=\(shortDebugText(windowTitle)) frame=\(frameText(frame(of: focusedWindow)))")
            instagramAXLog("fast focused input path used; deferred message snapshot until generation")
            return webInstagramContext(
                app: app,
                window: focusedWindow,
                input: fastInput,
                roomTitle: windowTitle.isEmpty ? "Instagram Messages" : windowTitle,
                chatMessages: []
            )
        }

        guard looksLikeInstagramMessagesWindow(focusedWindow, browserKind: browserKind, title: windowTitle) else {
            instagramAXLog("Instagram window found: false title=\(shortDebugText(windowTitle))")
            return .unsupportedApp
        }
        instagramAXLog("Instagram window found: true title=\(shortDebugText(windowTitle)) frame=\(frameText(frame(of: focusedWindow)))")

        let snapshot = instagramChatSnapshot(in: focusedWindow, browserKind: browserKind, limit: 20, logExtraction: false)
        let input = snapshot.inputField
        guard let input else {
            instagramAXLog("Instagram chat input found: false")
            return .noChatInput
        }
        logInstagramInsertionCandidate(input, window: focusedWindow, browserKind: browserKind, method: "context-detection")

        guard let roomTitle = snapshot.chatTitle else {
            instagramAXLog("Instagram room title found: false")
            return .unsupportedApp
        }

        return webInstagramContext(
            app: app,
            window: focusedWindow,
            input: input,
            roomTitle: roomTitle,
            chatMessages: snapshot.messages
        )
    }

    private func webInstagramContext(
        app: NSRunningApplication,
        window: AXUIElement,
        input: AXUIElement,
        roomTitle: String,
        chatMessages: [ChatMessage]
    ) -> SummonResult {
        let inputFrame = frame(of: input) ?? frame(of: window) ?? .zero

        return .ready(
            FocusedTextContext(
                source: .webInstagram,
                appName: app.localizedName ?? "Browser",
                bundleIdentifier: app.bundleIdentifier ?? "",
                element: input,
                windowElement: window,
                windowTitle: roomTitle,
                participantCount: 2,
                role: copyStringAttribute(input, kAXRoleAttribute) ?? "",
                value: textValue(of: input) ?? "",
                frame: inputFrame,
                windowFrame: frame(of: window),
                chatMessages: chatMessages
            )
        )
    }

    private func findFocusedKakaoChatInput(in appElement: AXUIElement) -> AXUIElement? {
        if let focusedElement = copyAttribute(appElement, kAXFocusedUIElementAttribute) as AXUIElement? {
            if let input = nearestInput(around: focusedElement) {
                return input
            }
        }

        guard let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement? else {
            return nil
        }

        guard looksLikeChatWindow(focusedWindow) else {
            return nil
        }

        let candidates = chatInputs(in: focusedWindow, maxVisited: 180)
        return bestInput(from: candidates)
    }

    private func nearestInput(around element: AXUIElement) -> AXUIElement? {
        if isKakaoChatInput(element) {
            return element
        }

        if let ancestor = inputAncestor(of: element) {
            return ancestor
        }

        if let childInput = bestInput(from: chatInputs(in: element, maxVisited: 70)) {
            return childInput
        }

        if let parent = copyAttribute(element, kAXParentAttribute) as AXUIElement?,
           let siblingInput = bestInput(from: chatInputs(in: parent, maxVisited: 90)) {
            return siblingInput
        }

        return nil
    }

    private func inputAncestor(of element: AXUIElement) -> AXUIElement? {
        var current = copyAttribute(element, kAXParentAttribute) as AXUIElement?
        var depth = 0

        while let currentElement = current, depth < 8 {
            if isKakaoChatInput(currentElement) {
                return currentElement
            }

            current = copyAttribute(currentElement, kAXParentAttribute) as AXUIElement?
            depth += 1
        }

        return nil
    }

    private func chatInputs(in root: AXUIElement, maxVisited: Int) -> [AXUIElement] {
        var queue: [AXUIElement] = [root]
        var matches: [AXUIElement] = []
        var visited = 0

        while !queue.isEmpty, visited < maxVisited {
            let element = queue.removeFirst()
            visited += 1

            if isKakaoChatInput(element) {
                matches.append(element)
            }

            if let children = copyAttribute(element, kAXChildrenAttribute) as [AXUIElement]? {
                queue.append(contentsOf: children)
            }
        }

        return matches
    }

    private func bestInput(from candidates: [AXUIElement]) -> AXUIElement? {
        candidates
            .compactMap { element -> (element: AXUIElement, frame: CGRect)? in
                guard let frame = frame(of: element), frame.width > 120, frame.height > 18 else {
                    return nil
                }
                return (element, frame)
            }
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 12 {
                    return lhs.frame.minY > rhs.frame.minY
                }
                return lhs.frame.width > rhs.frame.width
            }
            .first?
            .element
    }

    private func isKakaoChatInput(_ element: AXUIElement) -> Bool {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
        guard role == kAXTextAreaRole as String else {
            return false
        }

        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func looksLikeChatWindow(_ window: AXUIElement) -> Bool {
        let title = (copyStringAttribute(window, kAXTitleAttribute) ?? "").lowercased()

        if title.contains("친구") || title.contains("friends") {
            return false
        }

        if bestInput(from: chatInputs(in: window, maxVisited: 140)) != nil {
            return true
        }

        return false
    }

    private func looksLikeInstagramMessagesWindow(
        _ window: AXUIElement,
        browserKind: BrowserKind = .unknown,
        title rawTitle: String? = nil
    ) -> Bool {
        let title = (rawTitle ?? chatRoomTitle(for: window)).lowercased()
        if title.contains("instagram") && (title.contains("messages") || title.contains("direct")) {
            return true
        }

        if browserKind == .chrome,
           title.contains("instagram") {
            return true
        }

        if title.contains("instagram") {
            let texts = collectInstagramStaticTextCandidates(
                in: window,
                maxDepth: browserKind == .chrome ? 36 : 10,
                maxNodes: browserKind == .chrome ? 3000 : 220
            )
            return texts.contains { candidate in
                let normalized = candidate.text.lowercased()
                return normalized == "messages"
                    || normalized == "send"
                    || normalized == "message..."
                    || normalized == "instagram"
                    || normalized.contains("log in")
                    || normalized.contains("로그인")
                    || normalized.contains("active now")
            }
        }

        return false
    }

    private func collectVisibleInstagramMessages(
        in focusedWindow: AXUIElement,
        limit: Int = 20,
        logExtraction: Bool = true
    ) -> [ChatMessage] {
        guard isAccessibilityTrusted(), isWindowUsable(focusedWindow) else {
            return []
        }

        let browserKind = NSWorkspace.shared.frontmostApplication.map(browserKind(for:)) ?? .unknown
        return instagramChatSnapshot(
            in: focusedWindow,
            browserKind: browserKind,
            limit: limit,
            logExtraction: logExtraction
        ).messages
    }

    private func instagramChatSnapshot(
        in focusedWindow: AXUIElement,
        browserKind: BrowserKind,
        limit: Int,
        logExtraction: Bool
    ) -> InstagramChatSnapshot {
        let root = instagramParsingRoot(in: focusedWindow, browserKind: browserKind) ?? focusedWindow
        let rootFrame = frame(of: root)
        if logExtraction {
            instagramAXLog("HTML content subtree found: \(sameElement(root, focusedWindow) ? "fallback-window" : "true") frame=\(frameText(rootFrame))")
        }

        let windowFrame = frame(of: focusedWindow)
        let allCandidates = collectInstagramStaticTextCandidates(
            in: root,
            maxDepth: browserKind == .chrome ? 60 : 34,
            maxNodes: browserKind == .chrome ? 9000 : 3600
        )
        let roomTitle = instagramRoomTitle(in: focusedWindow, browserKind: browserKind, candidates: allCandidates)
        let activeStatus = instagramActiveStatus(from: allCandidates, windowFrame: windowFrame)
        let input = bestInstagramInput(in: focusedWindow, browserKind: browserKind)

        if logExtraction {
            instagramAXLog("number of text nodes collected: \(allCandidates.count)")
            instagramAXLog("chat title candidates: \(instagramRoomTitleCandidates(from: allCandidates, windowFrame: windowFrame).map { "\(shortDebugText($0.text)) \(frameText($0.frame))" }.joined(separator: " | "))")
            instagramAXLog("input field candidates: \(instagramInputCandidates(in: focusedWindow, browserKind: browserKind).prefix(8).map { "role=\($0.role) placeholder=\($0.placeholder ?? "") score=\($0.score) \(frameText($0.frame))" }.joined(separator: " | "))")
        }

        guard let roomTitle else {
            if logExtraction {
                instagramAXLog("final parsed messages: skipped because chat title was not found")
            }
            return InstagramChatSnapshot(
                browserKind: browserKind,
                chatTitle: nil,
                activeStatus: activeStatus,
                messages: [],
                inputField: input
            )
        }

        let messageCandidates = instagramMessageTextCandidates(
            allCandidates,
            windowFrame: windowFrame,
            roomTitle: roomTitle,
            logExtraction: logExtraction
        )
        let messages = inferInstagramMessages(
            from: messageCandidates,
            windowFrame: windowFrame,
            roomTitle: roomTitle,
            limit: limit,
            logExtraction: logExtraction
        )

        return InstagramChatSnapshot(
            browserKind: browserKind,
            chatTitle: roomTitle,
            activeStatus: activeStatus,
            messages: messages,
            inputField: input
        )
    }

    private func instagramParsingRoot(in window: AXUIElement, browserKind: BrowserKind) -> AXUIElement? {
        guard browserKind == .chrome else {
            return nil
        }

        let elements = [window] + descendants(of: window, maxDepth: 18, maxVisited: 2200)
        let candidates = elements.compactMap { element -> (element: AXUIElement, score: Int)? in
            let snapshot = snapshot(of: element)
            let identity = instagramElementIdentity(snapshot)
            var score = 0
            if identity.contains("html content") || identity.contains("web area") {
                score += 8
            }
            if identity.contains("instagram") {
                score += 4
            }
            if snapshot.role.lowercased().contains("web") {
                score += 2
            }
            guard score > 0 else {
                return nil
            }
            return (element, score)
        }

        return candidates.sorted { $0.score > $1.score }.first?.element
    }

    private func collectInstagramStaticTextCandidates(
        in root: AXUIElement,
        maxDepth: Int,
        maxNodes: Int
    ) -> [InstagramTextCandidate] {
        var queue: [(element: AXUIElement, depth: Int, parents: [InstagramAncestorSnapshot])] = [
            (root, 0, [])
        ]
        var visited = Set<AXElementID>()
        var candidates: [InstagramTextCandidate] = []
        var visitedCount = 0

        while !queue.isEmpty, visitedCount < maxNodes {
            let item = queue.removeFirst()
            let id = elementID(item.element)
            guard !visited.contains(id) else {
                continue
            }

            visited.insert(id)
            visitedCount += 1

            let snapshot = snapshot(of: item.element)
            if isInstagramTextNode(snapshot),
               let text = visibleText(from: snapshot),
               let frame = snapshot.frame {
                candidates.append(
                    InstagramTextCandidate(
                        text: normalizedInstagramText(text),
                        role: snapshot.role,
                        frame: frame,
                        parentChain: item.parents,
                        depth: item.depth
                    )
                )
            }

            guard item.depth < maxDepth else {
                continue
            }

            let ancestor = InstagramAncestorSnapshot(
                role: snapshot.role,
                value: snapshot.value,
                title: snapshot.title,
                description: snapshot.description,
                help: snapshot.help
            )
            let nextParents = Array((item.parents + [ancestor]).suffix(10))
            snapshot.children.forEach {
                queue.append(($0, item.depth + 1, nextParents))
            }
        }

        return uniqueInstagramCandidates(candidates)
    }

    private func isInstagramTextNode(_ snapshot: AXElementSnapshot) -> Bool {
        let role = snapshot.role.lowercased()
        guard !snapshot.isEditable else {
            return false
        }

        return snapshot.role == kAXStaticTextRole as String
            || role.contains("statictext")
            || role == "axtext"
            || role.contains("text")
            || snapshot.roleDescription?.lowercased().contains("text") == true
    }

    private func instagramMessageTextCandidates(
        _ candidates: [InstagramTextCandidate],
        windowFrame: CGRect?,
        roomTitle: String,
        logExtraction: Bool = false
    ) -> [InstagramTextCandidate] {
        let filtered = candidates.filter { candidate in
            let text = candidate.text
            guard !text.isEmpty,
                  candidate.frame.width > 2,
                  candidate.frame.height > 2 else {
                if logExtraction {
                    instagramAXLog("filtered out text=\(shortDebugText(text)) reason=empty-or-small frame=\(frameText(candidate.frame))")
                }
                return false
            }

            guard isInsideInstagramConversationColumn(candidate.frame, windowFrame: windowFrame) else {
                if logExtraction {
                    instagramAXLog("filtered out text=\(shortDebugText(text)) reason=outside-conversation frame=\(frameText(candidate.frame))")
                }
                return false
            }

            guard !isInstagramUIChromeText(text) else {
                if logExtraction {
                    instagramAXLog("filtered out text=\(shortDebugText(text)) reason=ui-chrome frame=\(frameText(candidate.frame))")
                }
                return false
            }

            guard !isInstagramHeaderCandidate(candidate, windowFrame: windowFrame, roomTitle: roomTitle) else {
                if logExtraction {
                    instagramAXLog("filtered out text=\(shortDebugText(text)) reason=header-title frame=\(frameText(candidate.frame))")
                }
                return false
            }

            return true
        }

        return filtered.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 3 {
                return lhs.frame.minY < rhs.frame.minY
            }

            return lhs.frame.minX < rhs.frame.minX
        }
    }

    private func isInsideInstagramConversationColumn(_ frame: CGRect, windowFrame: CGRect?) -> Bool {
        guard let windowFrame else {
            return true
        }

        let conversationMinX = windowFrame.minX + max(340, windowFrame.width * 0.25)
        let toolbarMaxY = windowFrame.minY + 72
        guard frame.midX >= conversationMinX,
              frame.midY >= toolbarMaxY,
              frame.midX <= windowFrame.maxX - 24 else {
            return false
        }

        return true
    }

    private func inferInstagramMessages(
        from candidates: [InstagramTextCandidate],
        windowFrame: CGRect?,
        roomTitle: String,
        limit: Int,
        logExtraction: Bool = false
    ) -> [ChatMessage] {
        let conversationFrame = unionFrame(candidates.map(\.frame))
        let referenceFrame = windowFrame ?? (conversationFrame.isNull ? nil : conversationFrame)
        let centerX = referenceFrame?.midX ?? conversationFrame.midX
        var messages: [ChatMessage] = []
        var pendingSender: String?
        var previousOtherSender: String?
        var pendingReplyDescription: String?
        var pendingQuotedText: String?
        var skipNextAsQuote = false

        for index in candidates.indices {
            let candidate = candidates[index]
            let nextCandidate = candidates.indices.contains(index + 1) ? candidates[index + 1] : nil

            if isInstagramReplyDescription(candidate.text) {
                pendingReplyDescription = candidate.text
                skipNextAsQuote = true
                if logExtraction {
                    instagramAXLog("reply metadata text=\(shortDebugText(candidate.text)) frame=\(frameText(candidate.frame))")
                }
                continue
            }

            if skipNextAsQuote,
               let pendingReplyDescription,
               !isInstagramSenderLabel(candidate, next: nextCandidate, centerX: centerX, windowFrame: referenceFrame),
               !isInstagramReplyDescription(candidate.text) {
                pendingQuotedText = candidate.text
                skipNextAsQuote = false
                if logExtraction {
                    instagramAXLog("reply quoted text=\(shortDebugText(candidate.text)) for=\(shortDebugText(pendingReplyDescription)) frame=\(frameText(candidate.frame))")
                }
                continue
            }
            skipNextAsQuote = false

            if isInstagramSenderLabel(candidate, next: nextCandidate, centerX: centerX, windowFrame: referenceFrame) {
                pendingSender = candidate.text
                previousOtherSender = candidate.text
                if logExtraction {
                    instagramAXLog("sender label text=\(shortDebugText(candidate.text)) frame=\(frameText(candidate.frame))")
                }
                continue
            }

            let isMine = isInstagramOutgoingMessage(candidate.frame, centerX: centerX, windowFrame: referenceFrame)
            let sender: String
            if isMine {
                sender = "Me"
                pendingSender = nil
            } else if let pendingSender {
                sender = pendingSender
            } else if let previousOtherSender {
                sender = previousOtherSender
            } else {
                sender = instagramFallbackSender(roomTitle: roomTitle)
            }

            let replyInfo = InstagramReplyInfo(description: pendingReplyDescription, quotedText: pendingQuotedText)
            let replyDebug = [replyInfo.description.map { "reply=\($0)" }, replyInfo.quotedText.map { "quote=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
            messages.append(
                ChatMessage(
                    sender: sender,
                    text: candidate.text,
                    frame: candidate.frame,
                    debugSource: "web-instagram x:\(Int(candidate.frame.minX)) y:\(Int(candidate.frame.minY)) \(replyDebug)"
                )
            )
            pendingReplyDescription = nil
            pendingQuotedText = nil

            if logExtraction {
                instagramAXLog("message candidate sender=\(sender) text=\(shortDebugText(candidate.text)) frame=\(frameText(candidate.frame))")
            }
        }

        let deduped = dedupeAdjacentInstagramMessages(messages)
        if logExtraction {
            instagramAXLog("final parsed messages: \(deduped.map { "\($0.sender):\(shortDebugText($0.text, maxLength: 40))" }.joined(separator: " | "))")
        }
        return Array(deduped.suffix(limit))
    }

    private func instagramFallbackSender(roomTitle: String) -> String {
        let title = normalizedInstagramText(roomTitle)
        guard !title.isEmpty,
              title != "Instagram DM",
              !isInstagramUIChromeText(title) else {
            return "other"
        }

        return title
    }

    private func isInstagramOutgoingMessage(_ frame: CGRect, centerX: CGFloat, windowFrame: CGRect?) -> Bool {
        if frame.midX > centerX + 36 {
            return true
        }

        if let windowFrame,
           frame.maxX > windowFrame.maxX - max(120, windowFrame.width * 0.22),
           frame.minX > centerX - 24 {
            return true
        }

        return false
    }

    private func isInstagramSenderLabel(
        _ candidate: InstagramTextCandidate,
        next: InstagramTextCandidate?,
        centerX: CGFloat,
        windowFrame: CGRect?
    ) -> Bool {
        let text = candidate.text
        guard text.count >= 2,
              text.count <= 32,
              !text.contains("\n"),
              !isInstagramOutgoingMessage(candidate.frame, centerX: centerX, windowFrame: windowFrame),
              !isInstagramUIChromeText(text),
              !looksLikeSentenceMessage(text) else {
            return false
        }

        guard let next else {
            return false
        }

        let verticalGap = next.frame.minY - candidate.frame.maxY
        guard verticalGap >= -2,
              verticalGap <= 52,
              !isInstagramOutgoingMessage(next.frame, centerX: centerX, windowFrame: windowFrame),
              next.frame.minX >= candidate.frame.minX - 18,
              next.frame.minX <= candidate.frame.minX + 120 else {
            return false
        }

        return true
    }

    private func looksLikeSentenceMessage(_ text: String) -> Bool {
        if text.contains("?") || text.contains("!") || text.contains(".") || text.contains("ㅋㅋ") || text.contains("ㅎ") {
            return true
        }

        if text.contains(" ") && text.count > 10 {
            return true
        }

        return false
    }

    private func isInstagramHeaderCandidate(
        _ candidate: InstagramTextCandidate,
        windowFrame: CGRect?,
        roomTitle: String
    ) -> Bool {
        let text = candidate.text
        let normalizedText = normalizedComparableInstagramText(text)
        let normalizedRoomTitle = normalizedComparableInstagramText(roomTitle)
        let parentIdentity = candidate.parentChain
            .flatMap { [$0.role, $0.value, $0.title, $0.description, $0.help] }
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if parentIdentity.contains("heading") || parentIdentity.contains("open the profile page") {
            return true
        }

        if !normalizedRoomTitle.isEmpty,
           normalizedText == normalizedRoomTitle {
            return true
        }

        guard let windowFrame else {
            return false
        }

        let headerMaxY = windowFrame.minY + min(max(windowFrame.height * 0.18, 88), 155)
        if candidate.frame.midY <= headerMaxY,
           candidate.frame.midX > windowFrame.minX + max(180, windowFrame.width * 0.20),
           candidate.frame.midX < windowFrame.maxX - 80,
           candidate.frame.height <= 36 {
            return true
        }

        return false
    }

    private func isInstagramUIChromeText(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let exact = [
            "instagram",
            "instagram · 메시지",
            "instagram · messages",
            "messages",
            "message",
            "message...",
            "google chrome",
            "search",
            "home",
            "explore",
            "reels",
            "notifications",
            "profile",
            "send",
            "active now",
            "seen",
            "reply",
            "like",
            "more",
            "menu",
            "new message",
            "your note",
            "you replied to yourself",
            "notes",
            "threads",
            "meta",
            "메시지",
            "검색",
            "홈",
            "탐색",
            "릴스",
            "알림",
            "프로필",
            "보내기",
            "답장",
            "좋아요",
            "더 보기",
            "활동 중",
            "메시지 입력...",
            "메시지 입력"
        ]

        if exact.contains(normalized) {
            return true
        }

        let prefixes = [
            "active ",
            "활동 중",
            "seen ",
            "open the profile page",
            "open the details pane of the chat",
            "liked a message",
            "you replied to",
            "sent an attachment",
            "typing",
            "instagram · 메시지 - google chrome",
            "instagram · messages - google chrome"
        ]

        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private func bestInstagramInput(in window: AXUIElement, browserKind: BrowserKind = .unknown) -> AXUIElement? {
        let candidates = instagramInputCandidates(in: window, browserKind: browserKind)
        if browserKind == .chrome,
           let pointerCandidate = instagramInputAtCurrentMouseLocation(in: window, candidates: candidates) {
            logInstagramInsertionCandidate(pointerCandidate, window: window, browserKind: browserKind, method: "mouse-location")
            return pointerCandidate.element
        }

        if browserKind == .chrome,
           let focusedCandidate = instagramFocusedInputCandidate(in: window, candidates: candidates) {
            logInstagramInsertionCandidate(focusedCandidate, window: window, browserKind: browserKind, method: "focused-candidate")
            return focusedCandidate.element
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            if abs(lhs.frame.minY - rhs.frame.minY) > 8 {
                return lhs.frame.minY > rhs.frame.minY
            }

            return lhs.frame.width > rhs.frame.width
        }
        .first?
        .element
    }

    private func fastFocusedInstagramInput(
        in window: AXUIElement,
        appElement: AXUIElement,
        browserKind: BrowserKind
    ) -> AXUIElement? {
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) as AXUIElement? else {
            return nil
        }

        let ancestorInfo = instagramInputAncestorInfo(for: focused, maxDepth: browserKind == .chrome ? 18 : 10)
        let candidate = ancestorInfo.textEntryElement ?? focused
        let snapshot = snapshot(of: candidate)
        guard let candidateFrame = snapshot.frame ?? frame(of: candidate) else {
            return nil
        }

        if let rejection = instagramInputRejectionReason(
            snapshot: snapshot,
            frame: candidateFrame,
            windowFrame: frame(of: window),
            ancestorChain: ancestorInfo.ancestorChain
        ) {
            instagramAXLog("fast focused input rejected: role=\(snapshot.role) frame=\(frameText(candidateFrame)) ancestors=\(ancestorInfo.ancestorChain) reason=\(rejection)")
            return nil
        }

        guard validateInstagramInsertionTarget(
            candidate,
            window: window,
            browserKind: browserKind,
            logPrefix: "fast focused input validation"
        ) else {
            return nil
        }

        let identity = [
            instagramElementIdentity(snapshot),
            ancestorInfo.identity,
            ancestorInfo.parentDescription
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        let role = snapshot.role.lowercased()
        let isTextRole = role.contains("text") || role.contains("textbox")
        let mentionsMessage = identity.contains("message")
            || identity.contains("메시지")
            || identity.contains("입력")
        let lowerArea = frame(of: window).map { candidateFrame.midY > $0.minY + $0.height * 0.62 } ?? true
        let insideConversationColumn = isInsideInstagramConversationColumn(candidateFrame, windowFrame: frame(of: window))
        let ambiguousSafariComposer = browserKind == .safari
            && lowerArea
            && insideConversationColumn
            && isSafariAmbiguousInstagramComposerCandidate(snapshot, frame: candidateFrame)

        guard isTextRole
            || snapshot.isEditable
            || ancestorInfo.hasTextEntryArea
            || mentionsMessage
            || ambiguousSafariComposer else {
            instagramAXLog("fast focused input rejected: role=\(snapshot.role) frame=\(frameText(candidateFrame)) ancestors=\(ancestorInfo.ancestorChain) reason=no-input-hint")
            return nil
        }

        if browserKind == .safari {
            guard lowerArea, insideConversationColumn else {
                instagramAXLog("fast focused input rejected: role=\(snapshot.role) frame=\(frameText(candidateFrame)) ancestors=\(ancestorInfo.ancestorChain) reason=safari-not-lower-conversation-area")
                return nil
            }
        }

        instagramAXLog("fast focused input accepted: role=\(snapshot.role) title=\(shortDebugText(snapshot.title ?? "")) desc=\(shortDebugText(snapshot.description ?? "")) value=\(shortDebugText(snapshot.value ?? "")) frame=\(frameText(candidateFrame)) ancestors=\(ancestorInfo.ancestorChain)")
        return candidate
    }

    private func instagramInputCandidates(in window: AXUIElement, browserKind: BrowserKind = .unknown) -> [InstagramInputCandidate] {
        let windowFrame = frame(of: window)
        let maxDepth = browserKind == .chrome ? 60 : 34
        let maxVisited = browserKind == .chrome ? 9000 : 3600
        let elements = [window] + descendants(of: window, maxDepth: maxDepth, maxVisited: maxVisited)
        return elements.compactMap { element -> InstagramInputCandidate? in
            let snapshot = snapshot(of: element)
            let ancestorInfo = instagramInputAncestorInfo(for: element, maxDepth: browserKind == .chrome ? 18 : 8)
            let candidateElement = browserKind == .chrome ? (ancestorInfo.textEntryElement ?? element) : element
            let candidateSnapshot = sameElement(candidateElement, element) ? snapshot : self.snapshot(of: candidateElement)
            let frameForLog = candidateSnapshot.frame ?? snapshot.frame
            let debugPrefix = "input candidate rejected: role=\(snapshot.role) title=\(shortDebugText(snapshot.title ?? "")) name=\(shortDebugText(snapshot.label ?? "")) desc=\(shortDebugText(snapshot.description ?? "")) value=\(shortDebugText(snapshot.value ?? "")) frame=\(frameText(frameForLog)) ancestors=\(ancestorInfo.ancestorChain) reason="
            guard let candidateFrame = frameForLog,
                  candidateFrame.width > 80,
                  candidateFrame.height >= 14 else {
                if browserKind == .safari, instagramPotentialInputIdentity(instagramElementIdentity(snapshot), ancestorChain: ancestorInfo.ancestorChain) {
                    instagramAXLog("\(debugPrefix)missing-or-small-frame")
                }
                return nil
            }

            let role = snapshot.role
            let text = [
                snapshot.value,
                snapshot.title,
                snapshot.description,
                snapshot.help,
                snapshot.label,
                snapshot.placeholder,
                snapshot.identifier,
                snapshot.roleDescription,
                ancestorInfo.identity
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            let isTextRole = role == kAXTextAreaRole as String
                || role == kAXTextFieldRole as String
                || role == "AXTextArea"
                || role == "AXTextField"
                || role.lowercased().contains("textbox")
                || role.lowercased().contains("text")
            let mentionsMessage = text.contains("message")
                || text.contains("메시지")
                || text.contains("입력")
            let lowerArea = windowFrame.map { candidateFrame.midY > $0.minY + $0.height * 0.62 } ?? true
            let insideConversationColumn = isInsideInstagramConversationColumn(candidateFrame, windowFrame: windowFrame)
            let editable = snapshot.isEditable || isSettableTextArea(element)
            let hasTextEntryAreaAncestor = ancestorInfo.hasTextEntryArea
            let hasBrowserAccessibilityAncestor = ancestorInfo.hasBrowserAccessibility
            let isChromeTextEntryGroup = browserKind == .chrome
                && hasTextEntryAreaAncestor
                && (role == "AXGroup" || role.lowercased().contains("group"))
            let isSafariAmbiguousComposer = browserKind == .safari
                && lowerArea
                && insideConversationColumn
                && isSafariAmbiguousInstagramComposerCandidate(snapshot, frame: candidateFrame)

            if let rejection = instagramInputRejectionReason(
                snapshot: snapshot,
                frame: candidateFrame,
                windowFrame: windowFrame,
                ancestorChain: ancestorInfo.ancestorChain
            ) {
                instagramAXLog("\(debugPrefix)\(rejection)")
                return nil
            }

            guard isTextRole || mentionsMessage || editable || isChromeTextEntryGroup || isSafariAmbiguousComposer else {
                if browserKind == .safari, lowerArea || insideConversationColumn || instagramPotentialInputIdentity(text, ancestorChain: ancestorInfo.ancestorChain) {
                    instagramAXLog("\(debugPrefix)no-text-or-composer-hint")
                }
                return nil
            }

            var score = 0
            if ancestorInfo.ancestorChain.lowercased().contains("main") { score += 4 }
            if isTextRole { score += 4 }
            if mentionsMessage { score += 5 }
            if lowerArea { score += 4 }
            if insideConversationColumn { score += 3 }
            if editable { score += browserKind == .chrome ? 7 : 4 }
            if hasTextEntryAreaAncestor { score += browserKind == .chrome ? 14 : 5 }
            if hasBrowserAccessibilityAncestor { score += browserKind == .chrome ? 3 : 1 }
            if isSafariAmbiguousComposer { score += 5 }
            if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String { score += 2 }
            if snapshot.placeholder.map(looksLikeInstagramInputPlaceholder) == true { score += 6 }
            if snapshot.label.map(looksLikeInstagramInputPlaceholder) == true { score += 5 }
            if snapshot.description.map(looksLikeInstagramInputPlaceholder) == true { score += 5 }
            if snapshot.title.map(looksLikeInstagramInputPlaceholder) == true { score += 5 }
            if candidateFrame.height > 80 { score -= browserKind == .chrome && hasTextEntryAreaAncestor ? 0 : 3 }
            if candidateFrame.midY < (windowFrame?.midY ?? candidateFrame.midY) { score -= 4 }
            if browserKind == .chrome,
               let windowFrame {
                let distanceFromBottom = windowFrame.maxY - candidateFrame.midY
                if distanceFromBottom < windowFrame.height * 0.22 { score += 6 }
                if candidateFrame.midX < windowFrame.minX + windowFrame.width * 0.34 { score -= 7 }
                if candidateFrame.width > max(260, windowFrame.width * 0.30) { score += 4 }
            }

            instagramAXLog("input candidate accepted: role=\(candidateSnapshot.role.isEmpty ? role : candidateSnapshot.role) title=\(shortDebugText(candidateSnapshot.title ?? snapshot.title ?? "")) name=\(shortDebugText(candidateSnapshot.label ?? snapshot.label ?? "")) desc=\(shortDebugText(candidateSnapshot.description ?? snapshot.description ?? "")) value=\(shortDebugText(candidateSnapshot.value ?? snapshot.value ?? "")) frame=\(frameText(candidateFrame)) ancestors=\(ancestorInfo.ancestorChain) score=\(score)")

            return InstagramInputCandidate(
                element: candidateElement,
                frame: candidateFrame,
                role: candidateSnapshot.role.isEmpty ? role : candidateSnapshot.role,
                placeholder: candidateSnapshot.placeholder ?? snapshot.placeholder,
                identity: text,
                parentDescription: ancestorInfo.parentDescription,
                ancestorChain: ancestorInfo.ancestorChain,
                hasTextEntryAreaAncestor: hasTextEntryAreaAncestor,
                hasBrowserAccessibilityAncestor: hasBrowserAccessibilityAncestor,
                keyboardFocused: candidateSnapshot.isFocused ?? snapshot.isFocused,
                score: score
            )
        }
    }

    private func instagramInputAtCurrentMouseLocation(
        in window: AXUIElement,
        candidates: [InstagramInputCandidate]
    ) -> InstagramInputCandidate? {
        guard let windowFrame = frame(of: window) else {
            return nil
        }

        let mouse = currentMousePointInAXCoordinates()
        guard windowFrame.insetBy(dx: -4, dy: -4).contains(mouse) else {
            return nil
        }

        let directHits = candidates.filter {
            $0.hasTextEntryAreaAncestor
                && $0.frame.insetBy(dx: -10, dy: -12).contains(mouse)
        }
        if let hit = directHits.sorted(by: instagramInputSort).first {
            return hit
        }

        let appPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let appPID else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(appPID)
        var elementAtPoint: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            appElement,
            Float(mouse.x),
            Float(mouse.y),
            &elementAtPoint
        )
        guard result == .success,
              let elementAtPoint else {
            return nil
        }

        let info = instagramInputAncestorInfo(for: elementAtPoint, maxDepth: 18)
        guard info.hasTextEntryArea,
              let elementFrame = frame(of: info.textEntryElement ?? elementAtPoint),
              isInsideInstagramConversationColumn(elementFrame, windowFrame: windowFrame),
              elementFrame.midY > windowFrame.minY + windowFrame.height * 0.60 else {
            return nil
        }

        let snapshot = snapshot(of: info.textEntryElement ?? elementAtPoint)
        return InstagramInputCandidate(
            element: info.textEntryElement ?? elementAtPoint,
            frame: elementFrame,
            role: snapshot.role,
            placeholder: snapshot.placeholder,
            identity: [
                instagramElementIdentity(snapshot),
                info.identity
            ].joined(separator: " "),
            parentDescription: info.parentDescription,
            ancestorChain: info.ancestorChain,
            hasTextEntryAreaAncestor: true,
            hasBrowserAccessibilityAncestor: info.hasBrowserAccessibility,
            keyboardFocused: snapshot.isFocused,
            score: 100
        )
    }

    private func instagramFocusedInputCandidate(
        in window: AXUIElement,
        candidates: [InstagramInputCandidate]
    ) -> InstagramInputCandidate? {
        guard let appPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(appPID)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) as AXUIElement? else {
            return nil
        }

        let info = instagramInputAncestorInfo(for: focused, maxDepth: 18)
        guard info.hasTextEntryArea,
              let focusedFrame = frame(of: info.textEntryElement ?? focused) else {
            return candidates.filter { $0.keyboardFocused == true }.sorted(by: instagramInputSort).first
        }

        if let candidate = candidates.first(where: { sameElement($0.element, info.textEntryElement ?? focused) }) {
            return candidate
        }

        let snapshot = snapshot(of: info.textEntryElement ?? focused)
        return InstagramInputCandidate(
            element: info.textEntryElement ?? focused,
            frame: focusedFrame,
            role: snapshot.role,
            placeholder: snapshot.placeholder,
            identity: [
                instagramElementIdentity(snapshot),
                info.identity
            ].joined(separator: " "),
            parentDescription: info.parentDescription,
            ancestorChain: info.ancestorChain,
            hasTextEntryAreaAncestor: true,
            hasBrowserAccessibilityAncestor: info.hasBrowserAccessibility,
            keyboardFocused: snapshot.isFocused,
            score: 95
        )
    }

    private func instagramInputSort(_ lhs: InstagramInputCandidate, _ rhs: InstagramInputCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        if abs(lhs.frame.minY - rhs.frame.minY) > 8 {
            return lhs.frame.minY > rhs.frame.minY
        }

        return lhs.frame.width > rhs.frame.width
    }

    private func instagramInputAncestorInfo(
        for element: AXUIElement,
        maxDepth: Int
    ) -> InstagramInputAncestorInfo {
        var current = copyAttribute(element, kAXParentAttribute) as AXUIElement?
        var depth = 0
        var textEntryElement: AXUIElement?
        var hasTextEntryArea = false
        var hasBrowserAccessibility = false
        var identities: [String] = []
        var chainLines: [String] = [instagramAncestorLine(for: element)]
        var parentDescription: String?

        while let currentElement = current, depth < maxDepth {
            let snapshot = snapshot(of: currentElement)
            let identity = instagramElementIdentity(snapshot)
            if depth == 0 {
                parentDescription = [
                    snapshot.description,
                    snapshot.roleDescription,
                    snapshot.title,
                    snapshot.value
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            identities.append(identity)
            chainLines.append(instagramAncestorLine(for: currentElement, snapshot: snapshot))

            if identity.contains("text entry area") {
                hasTextEntryArea = true
                if textEntryElement == nil {
                    textEntryElement = currentElement
                }
            }

            if identity.contains("browseraccessibilitycocoa")
                || identity.contains("html content")
                || identity.contains("web area") {
                hasBrowserAccessibility = true
            }

            current = copyAttribute(currentElement, kAXParentAttribute) as AXUIElement?
            depth += 1
        }

        return InstagramInputAncestorInfo(
            identity: identities.joined(separator: " "),
            parentDescription: parentDescription?.isEmpty == false ? parentDescription : nil,
            ancestorChain: chainLines.joined(separator: " > "),
            hasTextEntryArea: hasTextEntryArea,
            hasBrowserAccessibility: hasBrowserAccessibility,
            textEntryElement: textEntryElement
        )
    }

    private func validateInstagramInsertionTarget(
        _ element: AXUIElement,
        window: AXUIElement,
        browserKind: BrowserKind,
        logPrefix: String
    ) -> Bool {
        let snapshot = snapshot(of: element)
        let elementFrame = snapshot.frame ?? frame(of: element)
        let ancestorInfo = instagramInputAncestorInfo(for: element, maxDepth: browserKind == .chrome ? 18 : 10)
        let chain = ancestorInfo.ancestorChain.lowercased()
        let identity = [
            instagramElementIdentity(snapshot),
            ancestorInfo.identity,
            ancestorInfo.parentDescription
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        let validationText = "\(identity) \(chain)"

        if validationText.contains("thread list")
            || validationText.contains("navigation")
            || validationText.contains("search")
            || validationText.contains("search text field")
            || validationText.contains("사람 검색")
            || validationText.contains("스레드 검색") {
            instagramAXLog("\(logPrefix): rejected unsafe target reason=search-thread-navigation role=\(snapshot.role) frame=\(frameText(elementFrame)) ancestors=\(ancestorInfo.ancestorChain)")
            return false
        }

        if let elementFrame,
           !isInsideInstagramConversationColumn(elementFrame, windowFrame: frame(of: window)) {
            instagramAXLog("\(logPrefix): rejected unsafe target reason=outside-conversation-column role=\(snapshot.role) frame=\(frameText(elementFrame)) ancestors=\(ancestorInfo.ancestorChain)")
            return false
        }

        instagramAXLog("\(logPrefix): accepted role=\(snapshot.role) title=\(shortDebugText(snapshot.title ?? "")) desc=\(shortDebugText(snapshot.description ?? "")) value=\(shortDebugText(snapshot.value ?? "")) frame=\(frameText(elementFrame)) ancestors=\(ancestorInfo.ancestorChain)")
        return true
    }

    private func instagramInputRejectionReason(
        snapshot: AXElementSnapshot,
        frame: CGRect,
        windowFrame: CGRect?,
        ancestorChain: String
    ) -> String? {
        let identity = instagramElementIdentity(snapshot)
        let combined = "\(identity) \(ancestorChain)".lowercased()

        if combined.contains("search") || combined.contains("검색") {
            return "search-identity"
        }

        if combined.contains("search text field") || snapshot.role.lowercased().contains("search") {
            return "search-text-field-role"
        }

        if combined.contains("thread list") || combined.contains("navigation") {
            return "thread-list-or-navigation-ancestor"
        }

        if let windowFrame,
           frame.midX < windowFrame.minX + max(340, windowFrame.width * 0.25) {
            return "left-thread-list-region"
        }

        return nil
    }

    private func isSafariAmbiguousInstagramComposerCandidate(_ snapshot: AXElementSnapshot, frame: CGRect) -> Bool {
        let role = snapshot.role.lowercased()
        let identity = instagramElementIdentity(snapshot)
        let looksLikeGroup = role.contains("group") || role.contains("webaccessibilityobjectwrapper")
        let reasonableComposerSize = frame.width >= 160 && frame.height >= 18 && frame.height <= 96
        return looksLikeGroup
            && reasonableComposerSize
            && !identity.contains("search")
            && !identity.contains("검색")
    }

    private func instagramPotentialInputIdentity(_ identity: String, ancestorChain: String) -> Bool {
        let combined = "\(identity) \(ancestorChain)".lowercased()
        return combined.contains("search")
            || combined.contains("message")
            || combined.contains("메시지")
            || combined.contains("입력")
            || combined.contains("thread list")
            || combined.contains("navigation")
    }

    private func instagramAncestorLine(for element: AXUIElement) -> String {
        instagramAncestorLine(for: element, snapshot: snapshot(of: element))
    }

    private func instagramAncestorLine(for element: AXUIElement, snapshot: AXElementSnapshot) -> String {
        let parts = [
            snapshot.role,
            snapshot.subrole,
            snapshot.title,
            snapshot.description,
            snapshot.value,
            snapshot.label,
            snapshot.placeholder,
            snapshot.roleDescription
        ]
        .compactMap { visibleText($0) }
        .map { shortDebugText($0, maxLength: 42) }

        let identity = parts.isEmpty ? "nil" : parts.joined(separator: " ")
        return "\(identity) \(frameText(snapshot.frame ?? frame(of: element)))"
    }

    private func focusInstagramInput(
        in window: AXUIElement,
        appPID: pid_t?,
        fallbackElement: AXUIElement
    ) -> Bool {
        let browserKind = NSWorkspace.shared.frontmostApplication.map(browserKind(for:)) ?? .unknown
        let input: AXUIElement
        if let bestInput = bestInstagramInput(in: window, browserKind: browserKind),
           validateInstagramInsertionTarget(bestInput, window: window, browserKind: browserKind, logPrefix: "focus target validation") {
            input = bestInput
        } else if validateInstagramInsertionTarget(fallbackElement, window: window, browserKind: browserKind, logPrefix: "focus fallback validation") {
            input = fallbackElement
        } else {
            instagramAXLog("focus target validation failed: no safe Instagram DM composer target; refusing Search fallback")
            return false
        }
        let pid = appPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        logInstagramInsertionCandidate(input, window: window, browserKind: browserKind, method: "focus-start")

        if focusElementAndVerify(input, appPID: pid) {
            logInstagramInsertionCandidate(input, window: window, browserKind: browserKind, method: "AXValue-focus")
            return true
        }

        AXUIElementPerformAction(input, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.08)
        if verifyFocusedInput(appPID: pid) {
            logInstagramInsertionCandidate(input, window: window, browserKind: browserKind, method: "AXPress")
            return true
        }

        guard let inputFrame = frame(of: input) else {
            return false
        }

        clickAXFrameCenter(inputFrame)
        Thread.sleep(forTimeInterval: 0.08)

        if verifyFocusedInput(appPID: pid) {
            logInstagramInsertionCandidate(input, window: window, browserKind: browserKind, method: "click")
            return true
        }

        logInstagramInsertionCandidate(input, window: window, browserKind: browserKind, method: "focus-failed")
        return false
    }

    private func focusElementAndVerify(_ element: AXUIElement, appPID: pid_t?) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.04)
        return verifyFocusedInput(appPID: appPID)
    }

    private func verifyFocusedInput(appPID: pid_t?) -> Bool {
        let pid = appPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) as AXUIElement? else {
            return false
        }

        let role = (copyStringAttribute(focused, kAXRoleAttribute) ?? "").lowercased()
        let identity = [
            copyStringAttribute(focused, kAXValueAttribute),
            copyStringAttribute(focused, kAXTitleAttribute),
            copyStringAttribute(focused, kAXDescriptionAttribute),
            copyStringAttribute(focused, kAXHelpAttribute)
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return role.contains("text")
            || role.contains("textbox")
            || identity.contains("message")
            || identity.contains("메시지")
            || identity.contains("입력")
    }

    private func clickAXFrameCenter(_ frame: CGRect) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func instagramRoomTitle(
        in window: AXUIElement,
        browserKind: BrowserKind = .unknown,
        candidates: [InstagramTextCandidate]? = nil
    ) -> String? {
        if browserKind == .chrome {
            let textCandidates = candidates ?? collectInstagramStaticTextCandidates(in: window, maxDepth: 44, maxNodes: 6000)
            if let title = instagramRoomTitleCandidates(from: textCandidates, windowFrame: frame(of: window)).first?.text {
                return title
            }
        }

        if let title = instagramProfileHeaderTitle(in: window) {
            return title
        }

        let textCandidates = candidates ?? collectInstagramStaticTextCandidates(in: window, maxDepth: 28, maxNodes: 3200)
        if let title = instagramRoomTitleCandidates(from: textCandidates, windowFrame: frame(of: window)).first?.text {
            return title
        }

        return nil
    }

    private func instagramRoomTitleCandidates(
        from candidates: [InstagramTextCandidate],
        windowFrame: CGRect?
    ) -> [InstagramTextCandidate] {
        candidates.filter { candidate in
            let text = candidate.text
            guard isLikelyInstagramRoomTitle(text),
                  !looksLikeInstagramActiveStatus(text),
                  !looksLikeInstagramInputPlaceholder(text) else {
                return false
            }

            if let windowFrame {
                let headerMaxY = windowFrame.minY + min(max(windowFrame.height * 0.20, 96), 175)
                let conversationMinX = windowFrame.minX + max(260, windowFrame.width * 0.24)
                guard candidate.frame.midY <= headerMaxY,
                      candidate.frame.midX >= conversationMinX,
                      candidate.frame.midX <= windowFrame.maxX - 80 else {
                    return false
                }
            }

            return true
        }
        .sorted { lhs, rhs in
            let lhsEmoji = isEmojiOnlyInstagramText(lhs.text)
            let rhsEmoji = isEmojiOnlyInstagramText(rhs.text)
            if lhsEmoji != rhsEmoji {
                return lhsEmoji
            }

            if abs(lhs.frame.minY - rhs.frame.minY) > 3 {
                return lhs.frame.minY < rhs.frame.minY
            }

            if lhs.text.count != rhs.text.count {
                return lhs.text.count < rhs.text.count
            }

            return lhs.frame.minX < rhs.frame.minX
        }
    }

    private func instagramActiveStatus(from candidates: [InstagramTextCandidate], windowFrame: CGRect?) -> String? {
        candidates
            .filter { candidate in
                looksLikeInstagramActiveStatus(candidate.text)
                    && (windowFrame.map { candidate.frame.midY <= $0.minY + min(max($0.height * 0.23, 110), 190) } ?? true)
            }
            .sorted { $0.frame.minY < $1.frame.minY }
            .first?
            .text
    }

    private func instagramProfileHeaderTitle(in window: AXUIElement) -> String? {
        let windowFrame = frame(of: window)
        let elements = descendants(of: window, maxDepth: 18, maxVisited: 1800)
        let profileLinks = elements.compactMap { element -> (element: AXUIElement, frame: CGRect?)? in
            let snapshot = snapshot(of: element)
            let role = snapshot.role
            let identity = instagramElementIdentity(snapshot)
            let isLink = role == "AXLink" || role.lowercased().contains("link")
            guard isLink,
                  identity.contains("open the profile page of") else {
                return nil
            }

            if let windowFrame,
               let linkFrame = snapshot.frame {
                let headerMaxY = windowFrame.minY + min(max(windowFrame.height * 0.22, 96), 175)
                guard linkFrame.midY <= headerMaxY,
                      linkFrame.midX > windowFrame.minX + max(150, windowFrame.width * 0.16) else {
                    return nil
                }
            }

            return (element, snapshot.frame)
        }

        for profileLink in profileLinks {
            if let title = instagramHeadingTitle(inside: profileLink.element) {
                return title
            }
        }

        return nil
    }

    private func instagramHeadingTitle(inside link: AXUIElement) -> String? {
        let candidates = [link] + descendants(of: link, maxDepth: 6, maxVisited: 120)
        let headings = candidates.filter { element in
            let snapshot = snapshot(of: element)
            let identity = instagramElementIdentity(snapshot)
            return snapshot.role == "AXHeading"
                || snapshot.role.lowercased().contains("heading")
                || identity.contains("(heading)")
                || identity.contains(" heading")
        }

        for heading in headings {
            let headingSnapshot = snapshot(of: heading)
            let childTexts = descendants(of: heading, maxDepth: 3, maxVisited: 40)
                .compactMap { child -> (text: String, frame: CGRect?)? in
                    let childSnapshot = snapshot(of: child)
                    guard childSnapshot.role == kAXStaticTextRole as String,
                          let text = visibleText(from: childSnapshot),
                          !isInstagramUIChromeText(text) else {
                        return nil
                    }

                    return (normalizedInstagramText(text), childSnapshot.frame)
                }
                .sorted { lhs, rhs in
                    guard let lhsFrame = lhs.frame,
                          let rhsFrame = rhs.frame else {
                        return lhs.text.count > rhs.text.count
                    }

                    if abs(lhsFrame.minY - rhsFrame.minY) > 2 {
                        return lhsFrame.minY < rhsFrame.minY
                    }

                    return lhsFrame.minX < rhsFrame.minX
                }

            if let childTitle = childTexts.first?.text,
               isLikelyInstagramRoomTitle(childTitle) {
                return childTitle
            }

            if let ownTitle = visibleText(from: headingSnapshot).map(normalizedInstagramText),
               isLikelyInstagramRoomTitle(ownTitle) {
                return ownTitle
            }
        }

        return nil
    }

    private func isLikelyInstagramRoomTitle(_ text: String) -> Bool {
        let normalized = normalizedInstagramText(text)
        guard !normalized.isEmpty,
              normalized.count <= 80,
              !normalized.contains("\n"),
              !isInstagramUIChromeText(normalized) else {
            return false
        }

        return true
    }

    private func isInstagramReplyDescription(_ text: String) -> Bool {
        let normalized = normalizedInstagramText(text).lowercased()
        return (normalized.contains("님이") && normalized.contains("에게") && normalized.contains("보낸 답장"))
            || normalized.contains("replied to")
            || normalized.contains("replying to")
    }

    private func looksLikeInstagramActiveStatus(_ text: String) -> Bool {
        let normalized = normalizedInstagramText(text).lowercased()
        return normalized.contains("활동 중입니다")
            || normalized.contains("active now")
            || normalized.contains("active ")
            || normalized.contains("님이 활동 중")
    }

    private func looksLikeInstagramInputPlaceholder(_ text: String) -> Bool {
        let normalized = normalizedInstagramText(text).lowercased()
        return normalized == "message..."
            || normalized == "message"
            || normalized.contains("메시지 입력")
            || normalized.contains("message input")
    }

    private func isEmojiOnlyInstagramText(_ text: String) -> Bool {
        let scalars = normalizedInstagramText(text).unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else {
            return false
        }

        return scalars.allSatisfy { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.properties.isEmoji
                || scalar.properties.generalCategory == .nonspacingMark
                || scalar.value == 0xFE0F
                || scalar.value == 0x200D
        }
    }

    private func instagramElementIdentity(_ snapshot: AXElementSnapshot) -> String {
        [
            snapshot.role,
            snapshot.subrole,
            snapshot.value,
            snapshot.title,
            snapshot.description,
            snapshot.help,
            snapshot.label,
            snapshot.placeholder,
            snapshot.identifier,
            snapshot.roleDescription
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func normalizedInstagramText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedComparableInstagramText(_ text: String) -> String {
        normalizedInstagramText(text)
            .lowercased()
            .components(separatedBy: " (").first?
            .components(separatedBy: " [").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func uniqueInstagramCandidates(_ candidates: [InstagramTextCandidate]) -> [InstagramTextCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.text)|\(Int(candidate.frame.minX))|\(Int(candidate.frame.minY))"
            guard !seen.contains(key) else {
                return false
            }

            seen.insert(key)
            return true
        }
    }

    private func dedupeAdjacentInstagramMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages {
            if let last = result.last,
               last.sender == message.sender,
               last.text == message.text {
                continue
            }

            result.append(message)
        }

        return result
    }

    private func focus(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func raiseOwningWindow(for element: AXUIElement) {
        var current: AXUIElement? = element

        while let currentElement = current {
            let role = copyStringAttribute(currentElement, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole as String {
                AXUIElementPerformAction(currentElement, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(currentElement, kAXMainAttribute as CFString, kCFBooleanTrue)
                return
            }

            current = copyAttribute(currentElement, kAXParentAttribute) as AXUIElement?
        }
    }

    private func debugDescription(for element: AXUIElement) -> String {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? "nil"
        let subrole = copyStringAttribute(element, kAXSubroleAttribute) ?? "nil"
        let title = copyStringAttribute(element, kAXTitleAttribute) ?? ""
        let frameText = frame(of: element).map { "\($0)" } ?? "nil"
        return "role=\(role), subrole=\(subrole), title=\(title), frame=\(frameText)"
    }

    func participantCount(inChatWindow window: AXUIElement) -> Int? {
        participantCount(in: window)
    }

    private func context(for element: AXUIElement, app: NSRunningApplication, includeParticipantCount: Bool) -> SummonResult {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
        guard let inputFrame = frame(of: element) else {
            return .noTextFocus
        }

        let value = copyStringAttribute(element, kAXValueAttribute) ?? ""
        let window = owningWindow(for: element)
        let metadata = window.map {
            chatRoomMetadata(for: $0, includeParticipantCount: includeParticipantCount)
        } ?? ChatRoomMetadata(title: "", participantCount: nil)

        return .ready(
            FocusedTextContext(
                source: .kakaoTalk,
                appName: app.localizedName ?? "KakaoTalk",
                bundleIdentifier: app.bundleIdentifier ?? "",
                element: element,
                windowElement: window,
                windowTitle: metadata.title,
                participantCount: metadata.participantCount,
                role: role,
                value: value,
                frame: inputFrame,
                windowFrame: window.flatMap { frame(of: $0) },
                chatMessages: []
            )
        )
    }

    private func owningWindowFrame(for element: AXUIElement) -> CGRect? {
        owningWindow(for: element).flatMap { frame(of: $0) }
    }

    private func owningWindow(for element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0

        while let currentElement = current, depth < 12 {
            let role = copyStringAttribute(currentElement, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole as String {
                return currentElement
            }

            current = copyAttribute(currentElement, kAXParentAttribute) as AXUIElement?
            depth += 1
        }

        return nil
    }

    private func findChatTable(in window: AXUIElement) -> AXUIElement? {
        if let cached = cachedUsableChatTable(for: window) {
            return cached
        }

        let elements = descendants(of: window, maxDepth: 5, maxVisited: 120)

        if let table = elements.first(where: { element in
            let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
            let description = (copyStringAttribute(element, kAXDescriptionAttribute) ?? "").lowercased()
            return (role == kAXTableRole as String
                || role == "AXTable"
                || description.contains("fschattableview"))
        }) {
            cachedChatTable = table
            cachedChatWindowID = elementID(window)
            return table
        }

        if let table = elements.first(where: { !visibleRows(in: $0).rows.isEmpty }) {
            cachedChatTable = table
            cachedChatWindowID = elementID(window)
            return table
        }

        return nil
    }

    private func visibleRows(in table: AXUIElement) -> VisibleRowsResult {
        if let visibleRows = copyAttribute(table, kAXVisibleRowsAttribute as String) as [AXUIElement]?,
           !visibleRows.isEmpty {
            return VisibleRowsResult(rows: visibleRows, source: "AXVisibleRows")
        }

        if let visibleRows = copyAttribute(table, "AXVisibleRows") as [AXUIElement]?,
           !visibleRows.isEmpty {
            return VisibleRowsResult(rows: visibleRows, source: "AXVisibleRows")
        }

        let directRows = rows(from: table)
        if !directRows.isEmpty {
            return VisibleRowsResult(rows: directRows, source: "AXRows")
        }

        let tableFrame = frame(of: table)
        let fallbackRows: [AXUIElement]
        fallbackRows = descendants(of: table, maxDepth: 4, maxVisited: 120).filter {
            (copyStringAttribute($0, kAXRoleAttribute) ?? "") == "AXRow"
        }

        let rows = uniqueElements(fallbackRows)
            .filter { row in
                guard let rowFrame = frame(of: row), rowFrame.width > 20, rowFrame.height > 8 else {
                    return false
                }

                if let tableFrame {
                    return rowFrame.intersects(tableFrame.insetBy(dx: -8, dy: -8))
                }

                return true
            }
            .sorted { lhs, rhs in
                let lhsFrame = frame(of: lhs) ?? .zero
                let rhsFrame = frame(of: rhs) ?? .zero
                if abs(lhsFrame.minY - rhsFrame.minY) > 2 {
                    return lhsFrame.minY < rhsFrame.minY
                }
                return lhsFrame.minX < rhsFrame.minX
            }

        return VisibleRowsResult(rows: rows, source: "descendants")
    }

    private func rows(from element: AXUIElement) -> [AXUIElement] {
        if let rows = copyAttribute(element, "AXRows") as [AXUIElement]? {
            return rows
        }

        return children(of: element).filter {
            (copyStringAttribute($0, kAXRoleAttribute) ?? "") == "AXRow"
        }
    }

    private func isChatTableScrolledToBottom(_ table: AXUIElement) -> Bool? {
        guard let scrollBar = verticalScrollBar(for: table),
              let value = numericAttribute(scrollBar, kAXValueAttribute as String),
              let maxValue = numericAttribute(scrollBar, "AXMaxValue") else {
            return nil
        }

        let minValue = numericAttribute(scrollBar, "AXMinValue") ?? 0
        let tolerance = max(0.02, (maxValue - minValue) * 0.015)
        return maxValue - value <= tolerance
    }

    private func verticalScrollBar(for element: AXUIElement) -> AXUIElement? {
        if let scrollBar = copyAttribute(element, "AXVerticalScrollBar") as AXUIElement? {
            return scrollBar
        }

        return descendants(of: element, maxDepth: 3, maxVisited: 80).first { candidate in
            let role = copyStringAttribute(candidate, kAXRoleAttribute) ?? ""
            guard role == "AXScrollBar" else {
                return false
            }

            let orientation = (copyStringAttribute(candidate, "AXOrientation") ?? "").lowercased()
            if orientation.contains("vertical") {
                return true
            }

            guard let frame = frame(of: candidate) else {
                return false
            }

            return frame.height > frame.width
        }
    }

    private func numericAttribute(_ element: AXUIElement, _ attribute: String) -> Double? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success,
              let value = rawValue else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let double = value as? Double {
            return double
        }

        if let float = value as? Float {
            return Double(float)
        }

        if let int = value as? Int {
            return Double(int)
        }

        return nil
    }

    private func cachedUsableChatTable(for window: AXUIElement) -> AXUIElement? {
        guard cachedChatWindowID == elementID(window),
              let cachedChatTable else {
            return nil
        }

        return cachedChatTable
    }

    private func invalidateCachedChatTable() {
        cachedChatTable = nil
        cachedChatWindowID = nil
    }

    private func scanRowOnce(_ row: AXUIElement) -> RowScanResult {
        var queue: [(element: AXUIElement, depth: Int)] = [(row, 0)]
        var visited = Set<AXElementID>()
        var messageCandidates: [MessageTextCandidate] = []
        var senderCandidates: [(text: String, frame: CGRect)] = []
        var hasSystemFeedMarker = false

        while !queue.isEmpty, visited.count < 32, messageCandidates.count < 3 {
            let item = queue.removeFirst()
            let id = elementID(item.element)
            guard !visited.contains(id) else {
                continue
            }

            visited.insert(id)
            let snapshot = snapshot(of: item.element)
            let identity = [
                snapshot.role,
                snapshot.description,
                snapshot.help
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if identity.contains("fschatlogfeedview") || identity.contains("blktextview") {
                hasSystemFeedMarker = true
            }

            if snapshot.role == kAXTextAreaRole as String,
               !isSettableTextArea(item.element),
               let text = visibleText(from: snapshot),
               isLikelyMessageText(text),
               let frame = snapshot.frame {
                messageCandidates.append(MessageTextCandidate(text: text, frame: frame))
            }

            if snapshot.role == kAXStaticTextRole as String,
               let text = visibleText(from: snapshot),
               isLikelySenderText(text),
               let frame = snapshot.frame {
                senderCandidates.append((text, frame))
            }

            guard item.depth < 4 else {
                continue
            }

            snapshot.children.forEach {
                queue.append(($0, item.depth + 1))
            }
        }

        return RowScanResult(
            messageCandidates: uniqueMessageCandidates(messageCandidates),
            senderCandidates: uniqueSenderCandidates(senderCandidates),
            hasSystemFeedMarker: hasSystemFeedMarker
        )
    }

    private func senderCandidate(from rowScan: RowScanResult, messageFrame: CGRect, tableFrame: CGRect?) -> String? {
        if let tableFrame,
           !isIncomingMessageFrame(messageFrame, tableFrame: tableFrame) {
            return nil
        }

        return rowScan.senderCandidates
            .filter { isLikelySenderFrame($0.frame, messageFrame: messageFrame, tableFrame: tableFrame) }
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 2 {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.frame.minX < rhs.frame.minX
            }
            .first?
            .text
    }

    private func isLikelySenderFrame(_ candidateFrame: CGRect, messageFrame: CGRect, tableFrame: CGRect?) -> Bool {
        guard !candidateFrame.isNull, !messageFrame.isNull else {
            return false
        }

        if let tableFrame {
            let messageIsInIncomingColumn = isIncomingMessageFrame(messageFrame, tableFrame: tableFrame)
            let incomingX = tableFrame.minX + incomingMessageXOffset
            let senderIsInIncomingColumn = abs(candidateFrame.minX - incomingX) <= senderNameXTolerance

            guard messageIsInIncomingColumn, senderIsInIncomingColumn else {
                return false
            }

            return candidateFrame.minX < tableFrame.midX
        }

        let senderColumnTolerance: CGFloat = 12
        return candidateFrame.minX <= messageFrame.minX + senderColumnTolerance
            && candidateFrame.midX < messageFrame.midX
    }

    private func isOutgoingMessage(_ candidates: [MessageTextCandidate], tableFrame: CGRect?, row: AXUIElement) -> Bool {
        let referenceFrame = tableFrame ?? frame(of: row)
        guard let referenceFrame else {
            return false
        }

        let messageFrame = unionFrame(candidates.map(\.frame))
        if let tableFrame {
            if isIncomingMessageFrame(messageFrame, tableFrame: tableFrame) {
                return false
            }
        }

        return messageFrame.midX > referenceFrame.midX + 18
    }

    private func isIncomingMessageFrame(_ messageFrame: CGRect, tableFrame: CGRect) -> Bool {
        let incomingX = tableFrame.minX + incomingMessageXOffset
        return abs(messageFrame.minX - incomingX) <= incomingMessageXTolerance
    }

    private func unionFrame(_ frames: [CGRect]) -> CGRect {
        frames.reduce(CGRect.null) { partialResult, frame in
            partialResult.union(frame)
        }
    }

    private func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { hash, scalar in
            (hash &* 33) &+ Int(scalar.value)
        }
    }

    private func trimParsedRows(_ rows: [ParsedChatRow], messageLimit: Int) -> [ParsedChatRow] {
        let messageIndexes = rows.indices.filter { rows[$0].message != nil }
        guard messageIndexes.count > messageLimit,
              let startIndex = messageIndexes.dropFirst(messageIndexes.count - messageLimit).first else {
            return rows
        }

        return Array(rows[startIndex...])
    }

    private func snapshot(of element: AXUIElement) -> AXElementSnapshot {
        let attributes = [
            kAXRoleAttribute as String,
            kAXSubroleAttribute as String,
            kAXValueAttribute as String,
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            "AXLabel",
            "AXPlaceholderValue",
            "AXIdentifier",
            "AXRoleDescription",
            kAXFocusedAttribute as String,
            kAXEnabledAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
            kAXChildrenAttribute as String
        ]
        let values = copyMultipleAttributes(element, attributes)
        let positionValue = axValue(from: values[kAXPositionAttribute as String])
        let sizeValue = axValue(from: values[kAXSizeAttribute as String])
        var valueSettable = DarwinBoolean(false)
        let isEditable = (AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success
            && valueSettable.boolValue)
            || (values["AXRoleDescription"] as? String)?.lowercased().contains("editable") == true

        return AXElementSnapshot(
            role: values[kAXRoleAttribute as String] as? String ?? "",
            subrole: values[kAXSubroleAttribute as String] as? String,
            value: values[kAXValueAttribute as String] as? String,
            title: values[kAXTitleAttribute as String] as? String,
            description: values[kAXDescriptionAttribute as String] as? String,
            help: values[kAXHelpAttribute as String] as? String,
            label: values["AXLabel"] as? String,
            placeholder: values["AXPlaceholderValue"] as? String,
            identifier: values["AXIdentifier"] as? String,
            roleDescription: values["AXRoleDescription"] as? String,
            frame: frame(positionValue: positionValue, sizeValue: sizeValue),
            isFocused: values[kAXFocusedAttribute as String] as? Bool,
            isEnabled: values[kAXEnabledAttribute as String] as? Bool,
            isEditable: isEditable,
            children: values[kAXChildrenAttribute as String] as? [AXUIElement] ?? []
        )
    }

    private func copyMultipleAttributes(_ element: AXUIElement, _ attributes: [String]) -> [String: Any] {
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )

        guard result == .success,
              let valueArray = values as? [Any],
              valueArray.count == attributes.count else {
            return attributes.reduce(into: [String: Any]()) { partialResult, attribute in
                if let value: Any = copyAttribute(element, attribute) {
                    partialResult[attribute] = value
                }
            }
        }

        var resultValues: [String: Any] = [:]
        for (index, attribute) in attributes.enumerated() {
            let value = valueArray[index]
            if CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() {
                let axValue = value as! AXValue
                var axError = AXError.success
                if AXValueGetType(axValue) == .axError,
                   AXValueGetValue(axValue, .axError, &axError) {
                    continue
                }
            }

            resultValues[attribute] = value
        }

        return resultValues
    }

    private func isSettableTextArea(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func visibleText(from element: AXUIElement) -> String? {
        let candidates = [
            copyStringAttribute(element, kAXValueAttribute),
            copyStringAttribute(element, kAXTitleAttribute),
            copyStringAttribute(element, kAXDescriptionAttribute),
            copyStringAttribute(element, kAXHelpAttribute)
        ]

        for candidate in candidates {
            guard let text = visibleText(candidate) else {
                continue
            }

            return text
        }

        return nil
    }

    private func visibleText(from snapshot: AXElementSnapshot) -> String? {
        let candidates = [
            snapshot.value,
            snapshot.title,
            snapshot.description,
            snapshot.help,
            snapshot.label,
            snapshot.placeholder
        ]

        for candidate in candidates {
            guard let text = visibleText(candidate) else {
                continue
            }

            return text
        }

        return nil
    }

    private func visibleText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func chatRoomTitle(for window: AXUIElement) -> String {
        let title = visibleText(copyStringAttribute(window, kAXTitleAttribute)) ?? ""
        let withoutRoleSuffix = title
            .components(separatedBy: " (").first?
            .components(separatedBy: " [").first ?? title

        return withoutRoleSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chatRoomMetadata(for window: AXUIElement, includeParticipantCount: Bool = true) -> ChatRoomMetadata {
        ChatRoomMetadata(
            title: chatRoomTitle(for: window),
            participantCount: includeParticipantCount ? participantCount(in: window) : nil
        )
    }

    private func participantCount(in window: AXUIElement) -> Int? {
        let windowFrame = frame(of: window)
        let chatTableFrame = findChatTable(in: window).flatMap { frame(of: $0) }
        let candidates = descendants(of: window, maxDepth: 5, maxVisited: 180)
            .compactMap { element -> (count: Int, frame: CGRect)? in
                guard let count = participantCountCandidate(from: element),
                      let candidateFrame = frame(of: element),
                      isHeaderElementFrame(candidateFrame, windowFrame: windowFrame, chatTableFrame: chatTableFrame) else {
                    return nil
                }

                return (count: count, frame: candidateFrame)
            }
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 4 {
                    return lhs.frame.minY < rhs.frame.minY
                }

                return lhs.frame.minX < rhs.frame.minX
            }

        return candidates.first?.count
    }

    private func participantCountCandidate(from element: AXUIElement) -> Int? {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
        guard role == kAXButtonRole as String || role == "AXButton" else {
            return nil
        }

        let textCandidates = uniqueStrings([
            visibleText(copyStringAttribute(element, kAXTitleAttribute)),
            visibleText(copyStringAttribute(element, kAXValueAttribute))
        ].compactMap { $0 })

        for text in textCandidates {
            if let count = participantCount(from: text) {
                return count
            }
        }

        return nil
    }

    private func participantCount(from text: String) -> Int? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil,
              let count = Int(normalized),
              count > 1 else {
            return nil
        }

        return count
    }

    private func isHeaderElementFrame(_ frame: CGRect, windowFrame: CGRect?, chatTableFrame: CGRect?) -> Bool {
        if let windowFrame {
            guard frame.midX >= windowFrame.minX - 8,
                  frame.midX <= windowFrame.maxX + 8 else {
                return false
            }

            let headerHeight = min(max(windowFrame.height * 0.18, 84), 150)
            guard frame.midY >= windowFrame.minY - 8,
                  frame.midY <= windowFrame.minY + headerHeight else {
                return false
            }
        }

        if let chatTableFrame,
           frame.maxY > chatTableFrame.minY + 12 {
            return false
        }

        return true
    }

    private func isLikelyMessageText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isLikelyChromeText(normalized) else {
            return false
        }

        return true
    }

    private func isLikelySenderText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2,
              normalized.count <= 32,
              !isLikelyChromeText(normalized) else {
            return false
        }

        if normalized.contains("\n") {
            return false
        }

        return true
    }

    private func isLikelyChromeText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let chromeTexts = [
            "close",
            "minimize",
            "zoom",
            "search",
            "profile",
            "button",
            "검색",
            "친구",
            "채팅",
            "더보기",
            "이모티콘",
            "파일",
            "전송",
            "닫기",
            "초대",
            "사진",
            "보이스톡",
            "페이스톡"
        ]

        return chromeTexts.contains { normalized == $0 || normalized.contains($0) && normalized.count <= $0.count + 4 }
    }

    private func descendants(of root: AXUIElement, maxDepth: Int, maxVisited: Int) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visited = Set<AXElementID>()

        while !queue.isEmpty, results.count < maxVisited {
            let item = queue.removeFirst()
            let id = elementID(item.element)
            guard !visited.contains(id) else {
                continue
            }

            visited.insert(id)
            if item.depth > 0 {
                results.append(item.element)
            }

            guard item.depth < maxDepth else {
                continue
            }

            children(of: item.element).forEach {
                queue.append(($0, item.depth + 1))
            }
        }

        return results
    }

    private func treeLine(for element: AXUIElement) -> String {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? "nil"
        let value = visibleText(copyStringAttribute(element, kAXValueAttribute)).map { " value=\(shortDebugText($0))" } ?? ""
        let title = visibleText(copyStringAttribute(element, kAXTitleAttribute)).map { " title=\(shortDebugText($0))" } ?? ""
        let description = visibleText(copyStringAttribute(element, kAXDescriptionAttribute)).map { " desc=\(shortDebugText($0))" } ?? ""
        return "\(role)\(value)\(title)\(description) frame=\(frameText(frame(of: element)))"
    }

    private func compactElementDescription(_ element: AXUIElement) -> String {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? "nil"
        let description = visibleText(copyStringAttribute(element, kAXDescriptionAttribute)).map { " desc=\(shortDebugText($0))" } ?? ""
        let title = visibleText(copyStringAttribute(element, kAXTitleAttribute)).map { " title=\(shortDebugText($0))" } ?? ""
        return "role=\(role)\(description)\(title) frame=\(frameText(frame(of: element)))"
    }

    private func shortDebugText(_ text: String, maxLength: Int = 80) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: "\\n")
        guard oneLine.count > maxLength else {
            return oneLine
        }

        return String(oneLine.prefix(maxLength)) + "..."
    }

    private func frameText(_ frame: CGRect?) -> String {
        guard let frame else {
            return "nil"
        }

        return "(x:\(Int(frame.minX)), y:\(Int(frame.minY)), w:\(Int(frame.width)), h:\(Int(frame.height)))"
    }

    private func instagramAXLog(_ message: String) {
        NSLog("[Sayless Instagram AX] %@", message)
    }

    private func logInstagramInsertionCandidate(
        _ element: AXUIElement,
        window: AXUIElement,
        browserKind: BrowserKind,
        method: String
    ) {
        let snapshot = snapshot(of: element)
        let ancestorInfo = instagramInputAncestorInfo(for: element, maxDepth: browserKind == .chrome ? 18 : 8)
        instagramAXLog(
            [
                "browser: \(browserKind.rawValue)",
                "window title: \(shortDebugText(chatRoomTitle(for: window)))",
                "candidate role: \(snapshot.role)",
                "candidate parent description: \(shortDebugText(ancestorInfo.parentDescription ?? ""))",
                "candidate ancestors: \(ancestorInfo.ancestorChain)",
                "text entry area ancestor: \(ancestorInfo.hasTextEntryArea)",
                "BrowserAccessibility ancestor: \(ancestorInfo.hasBrowserAccessibility)",
                "candidate frame: \(frameText(snapshot.frame ?? frame(of: element)))",
                "keyboard focused: \(snapshot.isFocused.map(String.init) ?? "nil")",
                "insertion method: \(method)"
            ].joined(separator: " | ")
        )
    }

    private func logInstagramInsertionCandidate(
        _ candidate: InstagramInputCandidate,
        window: AXUIElement,
        browserKind: BrowserKind,
        method: String
    ) {
        instagramAXLog(
            [
                "browser: \(browserKind.rawValue)",
                "window title: \(shortDebugText(chatRoomTitle(for: window)))",
                "candidate role: \(candidate.role)",
                "candidate parent description: \(shortDebugText(candidate.parentDescription ?? ""))",
                "text entry area ancestor: \(candidate.hasTextEntryAreaAncestor)",
                "BrowserAccessibility ancestor: \(candidate.hasBrowserAccessibilityAncestor)",
                "candidate frame: \(frameText(candidate.frame))",
                "keyboard focused: \(candidate.keyboardFocused.map(String.init) ?? "nil")",
                "insertion method: \(method)"
            ].joined(separator: " | ")
        )
    }

    private func currentMousePointInAXCoordinates() -> CGPoint {
        let location = NSEvent.mouseLocation
        guard let screenFrame = NSScreen.screens.first?.frame else {
            return location
        }

        return CGPoint(x: location.x, y: screenFrame.maxY - location.y)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute) as [AXUIElement]? ?? []
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen = Set<AXElementID>()
        return elements.filter {
            let id = elementID($0)
            guard !seen.contains(id) else {
                return false
            }

            seen.insert(id)
            return true
        }
    }

    private func uniqueStrings(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter {
            guard !seen.contains($0) else {
                return false
            }

            seen.insert($0)
            return true
        }
    }

    private func uniqueMessageCandidates(_ candidates: [MessageTextCandidate]) -> [MessageTextCandidate] {
        var seen = Set<String>()
        return candidates.filter {
            guard !seen.contains($0.text) else {
                return false
            }

            seen.insert($0.text)
            return true
        }
    }

    private func uniqueSenderCandidates(_ candidates: [(text: String, frame: CGRect)]) -> [(text: String, frame: CGRect)] {
        var seen = Set<String>()
        return candidates.filter {
            let key = "\($0.text)-\(Int($0.frame.minX))-\(Int($0.frame.minY))"
            guard !seen.contains(key) else {
                return false
            }

            seen.insert(key)
            return true
        }
    }

    private func elementID(_ element: AXUIElement) -> AXElementID {
        CFHash(element)
    }

    private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute) as AXValue?,
              let sizeValue = copyAttribute(element, kAXSizeAttribute) as AXValue? else {
            return nil
        }

        return frame(positionValue: positionValue, sizeValue: sizeValue)
    }

    private func frame(positionValue: AXValue?, sizeValue: AXValue?) -> CGRect? {
        guard let positionValue, let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

        guard size.width > 1, size.height > 1 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func axValue(from value: Any?) -> AXValue? {
        guard let value,
              CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }

        return (value as! AXValue)
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as String?
    }

    private func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value as? T
    }
}
