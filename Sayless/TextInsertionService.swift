import AppKit
import ApplicationServices

final class TextInsertionService {
    func insert(_ text: String, into context: FocusedTextContext) {
        let reader = AccessibilityReader()
        guard let target = reader.insertionElement(for: context) else {
            return
        }
        let insertionContext = contextWithTarget(target, from: context, reader: reader)

        if isChromeWebInstagram(insertionContext) {
            insertIntoChromeWebInstagram(text, context: insertionContext, reader: reader)
            return
        }

        _ = reader.focusInput(for: insertionContext)

        if reader.setValue(text, into: target) {
            return
        }

        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        typeText(text)
    }

    private func contextWithTarget(
        _ target: AXUIElement,
        from context: FocusedTextContext,
        reader: AccessibilityReader
    ) -> FocusedTextContext {
        FocusedTextContext(
            source: context.source,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            element: target,
            windowElement: context.windowElement,
            windowTitle: context.windowTitle,
            participantCount: context.participantCount,
            role: (copyAttribute(target, kAXRoleAttribute as String) as String?) ?? context.role,
            value: reader.textValue(of: target) ?? context.value,
            frame: frame(of: target) ?? context.frame,
            windowFrame: context.windowFrame,
            chatMessages: context.chatMessages
        )
    }

    private func insertIntoChromeWebInstagram(
        _ text: String,
        context: FocusedTextContext,
        reader: AccessibilityReader
    ) {
        NSLog(
            "[Sayless Instagram AX] browser: Chrome | window title: %@ | insertion method: chrome-click-paste-start",
            context.windowTitle
        )

        _ = reader.focusInput(for: context)
        AXUIElementPerformAction(context.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.06)

        if !clickInputFrame(context.frame, windowFrame: context.windowFrame) {
            fallbackClickInstagramBottomInput(windowFrame: context.windowFrame)
            NSLog(
                "[Sayless Instagram AX] browser: Chrome | window title: %@ | insertion method: fallback click+paste",
                context.windowTitle
            )
        } else {
            NSLog(
                "[Sayless Instagram AX] browser: Chrome | window title: %@ | candidate role: %@ | candidate frame: %@ | insertion method: click+paste",
                context.windowTitle,
                context.role,
                frameText(context.frame)
            )
        }

        Thread.sleep(forTimeInterval: 0.10)
        writePasteboard(text)
        sendCommandV()
        Thread.sleep(forTimeInterval: 0.12)

        let focusedValue = focusedElementValue(bundleIdentifier: context.bundleIdentifier)
        let contextValue = reader.textValue(of: context.element)
        let success = [focusedValue, contextValue].compactMap { $0 }.contains { $0.contains(text) }
        NSLog(
            "[Sayless Instagram AX] browser: Chrome | window title: %@ | insertion method: click+paste | paste success: %@",
            context.windowTitle,
            success ? "true" : "unverified"
        )
    }

    private func isChromeWebInstagram(_ context: FocusedTextContext) -> Bool {
        guard context.source == .webInstagram else {
            return false
        }

        let appName = context.appName.lowercased()
        let bundleID = context.bundleIdentifier.lowercased()
        let windowTitle = context.windowTitle.lowercased()

        return (bundleID == "com.google.chrome" || bundleID.contains("chromium") || appName.contains("chrome"))
            && (windowTitle.contains("instagram") || bundleID == "com.google.chrome" || appName.contains("chrome"))
    }

    private func clickInputFrame(_ frame: CGRect, windowFrame: CGRect?) -> Bool {
        guard frame.width > 20,
              frame.height >= 8 else {
            return false
        }

        if let windowFrame {
            let lowerEnough = frame.midY > windowFrame.minY + windowFrame.height * 0.55
            let wideEnough = frame.width > min(220, windowFrame.width * 0.25)
            guard lowerEnough, wideEnough else {
                return false
            }
        }

        let xOffset = min(max(frame.width * 0.12, 24), frame.width * 0.50)
        let point = CGPoint(x: frame.minX + xOffset, y: frame.midY)
        click(point)
        return true
    }

    private func fallbackClickInstagramBottomInput(windowFrame: CGRect?) {
        guard let windowFrame else {
            return
        }

        let point = CGPoint(
            x: windowFrame.minX + windowFrame.width * 0.68,
            y: windowFrame.maxY - max(42, min(90, windowFrame.height * 0.08))
        )
        click(point)
    }

    private func writePasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func click(_ point: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

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

    private func focusedElementValue(bundleIdentifier: String) -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute as String) as AXUIElement? else {
            return nil
        }

        return copyAttribute(focused, kAXValueAttribute as String) as String?
    }

    private func frameText(_ frame: CGRect) -> String {
        "(x:\(Int(frame.minX)), y:\(Int(frame.minY)), w:\(Int(frame.width)), h:\(Int(frame.height)))"
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as String) as AXValue?,
              let sizeValue = copyAttribute(element, kAXSizeAttribute as String) as AXValue? else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func typeText(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            units.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
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
