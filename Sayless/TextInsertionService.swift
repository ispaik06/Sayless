import AppKit
import ApplicationServices

final class TextInsertionService {
    func insert(_ text: String, into context: FocusedTextContext) {
        let reader = AccessibilityReader()
        _ = reader.focusInput(for: context)

        if reader.setValue(text, into: context.element) {
            return
        }

        AXUIElementSetAttributeValue(context.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        typeText(text)
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
}
