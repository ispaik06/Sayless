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
    let value: String?
    let title: String?
    let description: String?
    let help: String?
    let frame: CGRect?
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
    let score: Int
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

    private func focusedWebInstagramTextContext(app: NSRunningApplication) -> SummonResult {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement?,
              isWindowUsable(focusedWindow),
              looksLikeInstagramMessagesWindow(focusedWindow) else {
            return .unsupportedApp
        }

        let input = bestInstagramInput(in: focusedWindow)
        guard let input else {
            return .noChatInput
        }

        guard let roomTitle = instagramRoomTitle(in: focusedWindow) else {
            return .unsupportedApp
        }

        let inputFrame = frame(of: input) ?? frame(of: focusedWindow) ?? .zero
        let messages: [ChatMessage] = []

        return .ready(
            FocusedTextContext(
                source: .webInstagram,
                appName: app.localizedName ?? "Browser",
                bundleIdentifier: app.bundleIdentifier ?? "",
                element: input,
                windowElement: focusedWindow,
                windowTitle: roomTitle,
                participantCount: 2,
                role: copyStringAttribute(input, kAXRoleAttribute) ?? "",
                value: textValue(of: input) ?? "",
                frame: inputFrame,
                windowFrame: frame(of: focusedWindow),
                chatMessages: messages
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

    private func looksLikeInstagramMessagesWindow(_ window: AXUIElement) -> Bool {
        let title = chatRoomTitle(for: window).lowercased()
        if title.contains("instagram") && (title.contains("messages") || title.contains("direct")) {
            return true
        }

        if title.contains("instagram") {
            let texts = collectInstagramStaticTextCandidates(in: window, maxDepth: 10, maxNodes: 220)
            return texts.contains { candidate in
                let normalized = candidate.text.lowercased()
                return normalized == "messages"
                    || normalized == "send"
                    || normalized == "message..."
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

        let roomTitle = instagramRoomTitle(in: focusedWindow) ?? "Instagram DM"
        let windowFrame = frame(of: focusedWindow)
        let allCandidates = collectInstagramStaticTextCandidates(in: focusedWindow, maxDepth: 30, maxNodes: 3000)
        let messageCandidates = instagramMessageTextCandidates(allCandidates, windowFrame: windowFrame, roomTitle: roomTitle)
        let messages = inferInstagramMessages(
            from: messageCandidates,
            windowFrame: windowFrame,
            roomTitle: roomTitle,
            limit: limit
        )

        return messages
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
            if snapshot.role == kAXStaticTextRole as String,
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

    private func instagramMessageTextCandidates(
        _ candidates: [InstagramTextCandidate],
        windowFrame: CGRect?,
        roomTitle: String
    ) -> [InstagramTextCandidate] {
        let filtered = candidates.filter { candidate in
            let text = candidate.text
            guard !text.isEmpty,
                  candidate.frame.width > 2,
                  candidate.frame.height > 2,
                  isInsideInstagramConversationColumn(candidate.frame, windowFrame: windowFrame),
                  !isInstagramUIChromeText(text),
                  !isInstagramHeaderCandidate(candidate, windowFrame: windowFrame, roomTitle: roomTitle) else {
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
        limit: Int
    ) -> [ChatMessage] {
        let conversationFrame = unionFrame(candidates.map(\.frame))
        let referenceFrame = windowFrame ?? (conversationFrame.isNull ? nil : conversationFrame)
        let centerX = referenceFrame?.midX ?? conversationFrame.midX
        var messages: [ChatMessage] = []
        var pendingSender: String?
        var senderLabels: [String] = []

        for index in candidates.indices {
            let candidate = candidates[index]
            let nextCandidate = candidates.indices.contains(index + 1) ? candidates[index + 1] : nil

            if isInstagramSenderLabel(candidate, next: nextCandidate, centerX: centerX, windowFrame: referenceFrame) {
                pendingSender = candidate.text
                senderLabels.append(candidate.text)
                continue
            }

            let isMine = isInstagramOutgoingMessage(candidate.frame, centerX: centerX, windowFrame: referenceFrame)
            let sender: String
            if isMine {
                sender = "Me"
                pendingSender = nil
            } else if let pendingSender {
                sender = pendingSender
            } else {
                sender = instagramFallbackSender(roomTitle: roomTitle)
            }

            messages.append(
                ChatMessage(
                    sender: sender,
                    text: candidate.text,
                    frame: candidate.frame,
                    debugSource: "web-instagram x:\(Int(candidate.frame.minX)) y:\(Int(candidate.frame.minY))"
                )
            )
        }

        let deduped = dedupeAdjacentInstagramMessages(messages)
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
            "messages",
            "message",
            "message...",
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
            "활동 중"
        ]

        if exact.contains(normalized) {
            return true
        }

        let prefixes = [
            "active ",
            "seen ",
            "open the profile page",
            "liked a message",
            "you replied to",
            "sent an attachment",
            "typing"
        ]

        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private func bestInstagramInput(in window: AXUIElement) -> AXUIElement? {
        let candidates = instagramInputCandidates(in: window)
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

    private func instagramInputCandidates(in window: AXUIElement) -> [InstagramInputCandidate] {
        let windowFrame = frame(of: window)
        let elements = [window] + descendants(of: window, maxDepth: 30, maxVisited: 3000)
        return elements.compactMap { element -> InstagramInputCandidate? in
            let snapshot = snapshot(of: element)
            guard let candidateFrame = snapshot.frame,
                  candidateFrame.width > 80,
                  candidateFrame.height >= 14 else {
                return nil
            }

            let role = snapshot.role
            let text = [
                snapshot.value,
                snapshot.title,
                snapshot.description,
                snapshot.help
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            let isTextRole = role == kAXTextAreaRole as String
                || role == kAXTextFieldRole as String
                || role == "AXTextArea"
                || role == "AXTextField"
                || role.lowercased().contains("text")
            let mentionsMessage = text.contains("message")
                || text.contains("메시지")
                || text.contains("입력")
            let lowerArea = windowFrame.map { candidateFrame.midY > $0.minY + $0.height * 0.62 } ?? true

            guard isTextRole || mentionsMessage else {
                return nil
            }

            var score = 0
            if isTextRole { score += 4 }
            if mentionsMessage { score += 5 }
            if lowerArea { score += 4 }
            if isSettableTextArea(element) { score += 2 }
            if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String { score += 2 }

            return InstagramInputCandidate(element: element, frame: candidateFrame, score: score)
        }
    }

    private func focusInstagramInput(
        in window: AXUIElement,
        appPID: pid_t?,
        fallbackElement: AXUIElement
    ) -> Bool {
        let input = bestInstagramInput(in: window) ?? fallbackElement
        let pid = appPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier

        if focusElementAndVerify(input, appPID: pid) {
            return true
        }

        guard let inputFrame = frame(of: input) else {
            return false
        }

        clickAXFrameCenter(inputFrame)
        Thread.sleep(forTimeInterval: 0.08)

        if verifyFocusedInput(appPID: pid) {
            return true
        }

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

        return role.contains("text") || identity.contains("message") || identity.contains("메시지")
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

    private func instagramRoomTitle(in window: AXUIElement) -> String? {
        if let title = instagramProfileHeaderTitle(in: window) {
            return title
        }

        return nil
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

    private func instagramElementIdentity(_ snapshot: AXElementSnapshot) -> String {
        [
            snapshot.role,
            snapshot.value,
            snapshot.title,
            snapshot.description,
            snapshot.help
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
            kAXValueAttribute as String,
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
            kAXChildrenAttribute as String
        ]
        let values = copyMultipleAttributes(element, attributes)
        let positionValue = axValue(from: values[kAXPositionAttribute as String])
        let sizeValue = axValue(from: values[kAXSizeAttribute as String])

        return AXElementSnapshot(
            role: values[kAXRoleAttribute as String] as? String ?? "",
            value: values[kAXValueAttribute as String] as? String,
            title: values[kAXTitleAttribute as String] as? String,
            description: values[kAXDescriptionAttribute as String] as? String,
            help: values[kAXHelpAttribute as String] as? String,
            frame: frame(positionValue: positionValue, sizeValue: sizeValue),
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
            snapshot.help
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
