import AppKit
import ApplicationServices

struct FocusedTextContext {
    let appName: String
    let bundleIdentifier: String
    let element: AXUIElement
    let windowElement: AXUIElement?
    let windowTitle: String
    let role: String
    let value: String
    let frame: CGRect
    let windowFrame: CGRect?
    let chatMessages: [ChatMessage]
}

struct ChatMessage {
    let sender: String
    let text: String
    let frame: CGRect
    let debugSource: String?
}

private struct MessageTextCandidate {
    let text: String
    let frame: CGRect
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
    private let logPrefix = "[Sayless][AX]"
    private let incomingMessageXOffset: CGFloat = 60
    private let incomingMessageXTolerance: CGFloat = 22
    private let senderNameXTolerance: CGFloat = 28
    private typealias AXElementID = UInt
    private var cachedChatTable: AXUIElement?
    private var cachedChatWindowID: AXElementID?

    func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func focusedKakaoTextContext() -> SummonResult {
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
        return context(for: input, app: app)
    }

    func setValue(_ text: String, into element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
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

        guard let chatTable = findChatTable(in: focusedWindow) else {
            return []
        }

        let tableFrame = frame(of: chatTable)
        let parseLimit = min(limit + 6, 26)
        let rows = Array(visibleRows(in: chatTable).suffix(parseLimit))
        var parsedRows: [ParsedChatRow] = []
        var inheritedSender = "Unknown"

        for row in rows {
            let messageCandidates = messageTextCandidates(in: row)
            guard !messageCandidates.isEmpty else { continue }

            let text = messageCandidates.map(\.text).joined(separator: "\n")
            if isSystemFeedRow(row) {
                parsedRows.append(.system(text: text, frame: unionFrame(messageCandidates.map(\.frame))))
                continue
            }

            let messageFrame = unionFrame(messageCandidates.map(\.frame))
            let isMine = isOutgoingMessage(messageCandidates, tableFrame: tableFrame, row: row)
            let explicitSender = isMine ? nil : senderCandidate(in: row, messageFrame: messageFrame, tableFrame: tableFrame)
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
        let finalMessages = finalRows.compactMap(\.message)

        print("\(logPrefix) Latest visible messages:")
        if finalRows.isEmpty {
            print("\(logPrefix)   <none>")
        } else {
            printParsedRows(finalRows)
        }

        return finalMessages
    }

    func printKakaoAccessibilityTree(maxDepth: Int = 5) {
        guard isAccessibilityTrusted() else {
            print("\(logPrefix) Accessibility permission missing")
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              isKakaoTalk(app) else {
            print("\(logPrefix) Cannot print tree because frontmost app is not KakaoTalk")
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedWindow = copyAttribute(appElement, kAXFocusedWindowAttribute) as AXUIElement? else {
            print("\(logPrefix) Cannot print tree because focused KakaoTalk window is missing")
            return
        }

        print("\(logPrefix) Accessibility tree:")
        var visited = Set<AXElementID>()
        printTree(focusedWindow, depth: 0, maxDepth: maxDepth, visited: &visited)
    }

    private func isKakaoTalk(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        return name.contains("kakaotalk") || name.contains("kakao") || bundleID.contains("kakao")
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

    private func context(for element: AXUIElement, app: NSRunningApplication) -> SummonResult {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
        guard let inputFrame = frame(of: element) else {
            return .noTextFocus
        }

        let value = copyStringAttribute(element, kAXValueAttribute) ?? ""
        let window = owningWindow(for: element)
        return .ready(
            FocusedTextContext(
                appName: app.localizedName ?? "KakaoTalk",
                bundleIdentifier: app.bundleIdentifier ?? "",
                element: element,
                windowElement: window,
                windowTitle: window.map { chatRoomTitle(for: $0) } ?? "",
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
                && !rows(from: element).isEmpty
        }) {
            cachedChatTable = table
            cachedChatWindowID = elementID(window)
            return table
        }

        if let table = elements.first(where: { rows(from: $0).count >= 2 }) {
            cachedChatTable = table
            cachedChatWindowID = elementID(window)
            return table
        }

        return nil
    }

    private func visibleRows(in table: AXUIElement) -> [AXUIElement] {
        let directRows = rows(from: table)
        if !directRows.isEmpty {
            return directRows
        }

        let tableFrame = frame(of: table)
        let fallbackRows: [AXUIElement]
        fallbackRows = descendants(of: table, maxDepth: 4, maxVisited: 120).filter {
            (copyStringAttribute($0, kAXRoleAttribute) ?? "") == "AXRow"
        }

        return uniqueElements(fallbackRows)
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
    }

    private func rows(from element: AXUIElement) -> [AXUIElement] {
        if let rows = copyAttribute(element, "AXRows") as [AXUIElement]? {
            return rows
        }

        return children(of: element).filter {
            (copyStringAttribute($0, kAXRoleAttribute) ?? "") == "AXRow"
        }
    }

    private func cachedUsableChatTable(for window: AXUIElement) -> AXUIElement? {
        guard cachedChatWindowID == elementID(window),
              let cachedChatTable,
              !rows(from: cachedChatTable).isEmpty else {
            cachedChatTable = nil
            cachedChatWindowID = nil
            return nil
        }

        return cachedChatTable
    }

    private func messageTextCandidates(in row: AXUIElement) -> [MessageTextCandidate] {
        var queue: [(element: AXUIElement, depth: Int)] = [(row, 0)]
        var visited = Set<AXElementID>()
        var candidates: [MessageTextCandidate] = []

        while !queue.isEmpty, visited.count < 22, candidates.count < 2 {
            let item = queue.removeFirst()
            let id = elementID(item.element)
            guard !visited.contains(id) else {
                continue
            }

            visited.insert(id)

            let role = copyStringAttribute(item.element, kAXRoleAttribute) ?? ""
            if role == kAXTextAreaRole as String,
               !isSettableTextArea(item.element),
               let text = messageText(from: item.element),
               let frame = frame(of: item.element) {
                candidates.append(MessageTextCandidate(text: text, frame: frame))
            }

            guard item.depth < 3 else {
                continue
            }

            children(of: item.element).forEach {
                queue.append(($0, item.depth + 1))
            }
        }

        return uniqueMessageCandidates(candidates)
    }

    private func senderCandidate(in row: AXUIElement, messageFrame: CGRect, tableFrame: CGRect?) -> String? {
        if let tableFrame,
           !isIncomingMessageFrame(messageFrame, tableFrame: tableFrame) {
            return nil
        }

        return descendants(of: row, maxDepth: 4, maxVisited: 38)
            .filter { (copyStringAttribute($0, kAXRoleAttribute) ?? "") == kAXStaticTextRole as String }
            .compactMap { element -> (text: String, frame: CGRect)? in
                guard let text = visibleText(from: element),
                      let frame = frame(of: element),
                      isLikelySenderText(text),
                      isLikelySenderFrame(frame, messageFrame: messageFrame, tableFrame: tableFrame) else {
                    return nil
                }

                return (text, frame)
            }
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

    private func trimParsedRows(_ rows: [ParsedChatRow], messageLimit: Int) -> [ParsedChatRow] {
        let messageIndexes = rows.indices.filter { rows[$0].message != nil }
        guard messageIndexes.count > messageLimit,
              let startIndex = messageIndexes.dropFirst(messageIndexes.count - messageLimit).first else {
            return rows
        }

        return Array(rows[startIndex...])
    }

    private func printParsedRows(_ rows: [ParsedChatRow]) {
        var currentSender: String?

        for row in rows {
            switch row {
            case let .system(text, _):
                currentSender = nil
                print("\(logPrefix) [System] \(text)")
            case let .message(message):
                if currentSender != message.sender {
                    currentSender = message.sender
                    print("\(logPrefix) \(message.sender):")
                }

                message.text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .forEach { line in
                        print("\(logPrefix) \(line)")
                    }
            }
        }
    }

    private func messageText(from element: AXUIElement) -> String? {
        guard let text = visibleText(from: element),
              isLikelyMessageText(text) else {
            return nil
        }

        return text
    }

    private func isSystemFeedRow(_ row: AXUIElement) -> Bool {
        let markers = ["fschatlogfeedview", "blktextview"]
        var queue: [(element: AXUIElement, depth: Int)] = [(row, 0)]
        var visited = Set<AXElementID>()

        while !queue.isEmpty, visited.count < 18 {
            let item = queue.removeFirst()
            let id = elementID(item.element)
            guard !visited.contains(id) else {
                continue
            }

            visited.insert(id)
            let identity = [
                copyStringAttribute(item.element, kAXRoleAttribute),
                copyStringAttribute(item.element, kAXDescriptionAttribute),
                copyStringAttribute(item.element, kAXHelpAttribute)
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if markers.contains(where: { identity.contains($0) }) {
                return true
            }

            guard item.depth < 3 else {
                continue
            }

            children(of: item.element).forEach {
                queue.append(($0, item.depth + 1))
            }
        }

        return false
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

    private func printTree(_ element: AXUIElement, depth: Int, maxDepth: Int, visited: inout Set<AXElementID>) {
        let id = elementID(element)
        guard !visited.contains(id) else {
            print("\(String(repeating: "  ", count: depth))<cycle>")
            return
        }

        visited.insert(id)
        print("\(String(repeating: "  ", count: depth))\(treeLine(for: element))")

        guard depth < maxDepth else {
            return
        }

        children(of: element).prefix(80).forEach {
            printTree($0, depth: depth + 1, maxDepth: maxDepth, visited: &visited)
        }
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

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

        guard size.width > 1, size.height > 1 else {
            return nil
        }

        return CGRect(origin: position, size: size)
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
