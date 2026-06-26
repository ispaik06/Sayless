import AppKit

struct KeyboardShortcutSpec: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt
    let key: String

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    var title: String {
        "\(modifierTitle)\(key)"
    }

    var hasModifier: Bool {
        !modifiers.isEmpty
    }

    static func make(from event: NSEvent, requiresModifier: Bool) -> KeyboardShortcutSpec? {
        let modifiers = normalizedModifiers(from: event)
        guard !requiresModifier || !modifiers.isEmpty else {
            return nil
        }

        guard let key = displayKey(for: event) else {
            return nil
        }

        return KeyboardShortcutSpec(
            keyCode: event.keyCode,
            modifiersRawValue: modifiers.rawValue,
            key: key
        )
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.normalizedModifiers(from: event) == modifiers
    }

    private var modifierTitle: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        return parts.isEmpty ? "" : "\(parts.joined(separator: " ")) "
    }

    private static func normalizedModifiers(from event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .option, .shift, .control])
    }

    private static func displayKey(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return nil
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let raw = event.charactersIgnoringModifiers ?? event.characters ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return trimmed.uppercased()
        }
    }
}
