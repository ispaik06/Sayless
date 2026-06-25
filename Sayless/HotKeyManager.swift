import AppKit
import Carbon
import Foundation

enum ShortcutOption: String, CaseIterable, Identifiable {
    case optionSpace
    case optionShiftSpace
    case optionShiftCommandSpace
    case doubleTapOption
    case doubleTapRightOption
    case doubleTapRightCommand
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .optionShiftSpace: "⌥ ⇧ Space"
        case .optionShiftCommandSpace: "⌥ ⇧ ⌘ Space"
        case .doubleTapOption: "Double-tap ⌥"
        case .doubleTapRightOption: "Double-tap ⌥ (Right)"
        case .doubleTapRightCommand: "Double-tap ⌘ (Right)"
        case .custom: "Custom"
        }
    }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var lastTap: (keyCode: UInt16, time: TimeInterval)?

    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installCarbonHandler()
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func configure(_ option: ShortcutOption) {
        unregister()

        switch option {
        case .optionSpace:
            registerSpace(modifiers: optionKey)
        case .optionShiftSpace:
            registerSpace(modifiers: optionKey | shiftKey)
        case .optionShiftCommandSpace:
            registerSpace(modifiers: optionKey | shiftKey | cmdKey)
        case .doubleTapOption:
            installDoubleTapMonitor(acceptedKeyCodes: [58, 61])
        case .doubleTapRightOption:
            installDoubleTapMonitor(acceptedKeyCodes: [61])
        case .doubleTapRightCommand:
            installDoubleTapMonitor(acceptedKeyCodes: [54])
        case .custom:
            break
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }

        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }

        lastTap = nil
    }

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerSpace(modifiers: Int) {
        let hotKeyID = EventHotKeyID(signature: OSType("SLSH"), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
        }
    }

    private func installDoubleTapMonitor(acceptedKeyCodes: Set<UInt16>) {
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.handleFlagsChanged(event, acceptedKeyCodes: acceptedKeyCodes)
            return event
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: handler)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, acceptedKeyCodes: acceptedKeyCodes)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent, acceptedKeyCodes: Set<UInt16>) {
        let keyCode = event.keyCode
        guard acceptedKeyCodes.contains(keyCode), modifierIsDown(for: keyCode, flags: event.modifierFlags) else {
            return
        }

        let now = event.timestamp
        if let lastTap, lastTap.keyCode == keyCode, now - lastTap.time < 0.34 {
            self.lastTap = nil
            action()
        } else {
            lastTap = (keyCode, now)
        }
    }

    private func modifierIsDown(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 58, 61:
            flags.contains(.option)
        case 54, 55:
            flags.contains(.command)
        default:
            false
        }
    }
}

private extension OSType {
    init(_ string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
