import AppKit
import ApplicationServices

struct FocusedTextContext {
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

struct ChatMessage {
    let sender: String
    let text: String
    let frame: CGRect
    let debugSource: String?
}

struct ChatTimelineSignature: Equatable {
    let tail: [ChatMessageFingerprint]

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
        let metadata = window.map { chatRoomMetadata(for: $0) } ?? ChatRoomMetadata(title: "", participantCount: nil)

        return .ready(
            FocusedTextContext(
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

    private func chatRoomMetadata(for window: AXUIElement) -> ChatRoomMetadata {
        ChatRoomMetadata(
            title: chatRoomTitle(for: window),
            participantCount: participantCount(in: window)
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
