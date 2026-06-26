import AppKit

final class AppActivationManager {
    static let shared = AppActivationManager()

    private var appWindowIDs: Set<ObjectIdentifier> = []
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func enterMenuBarModeIfPossible() {
        updateActivationPolicy()
    }

    func showAppWindow(_ window: NSWindow, prepareForDisplay: ((NSWindow) -> Void)? = nil) {
        trackAppWindow(window)
        let originalLevel = window.level

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            self.bringAppWindowForward(window, elevated: true)
            prepareForDisplay?(window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.bringAppWindowForward(window, elevated: true)
                prepareForDisplay?(window)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                window.level = originalLevel
                prepareForDisplay?(window)
                self.bringAppWindowForward(window)
            }
        }
    }

    private func bringAppWindowForward(_ window: NSWindow, elevated: Bool = false) {
        if elevated {
            window.level = .floating
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func trackAppWindow(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        appWindowIDs.insert(windowID)
        window.isReleasedWhenClosed = false

        guard closeObservers[windowID] == nil else {
            return
        }

        closeObservers[windowID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.untrackAppWindow(with: windowID)
        }
    }

    private func untrackAppWindow(with windowID: ObjectIdentifier) {
        appWindowIDs.remove(windowID)

        if let observer = closeObservers.removeValue(forKey: windowID) {
            NotificationCenter.default.removeObserver(observer)
        }

        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = appWindowIDs.isEmpty ? .accessory : .regular
        NSApp.setActivationPolicy(policy)
    }
}
