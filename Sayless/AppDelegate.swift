import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        terminatePreviousInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func terminatePreviousInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessID }
            .forEach { app in
                if !app.terminate() {
                    app.forceTerminate()
                }
            }
    }
}
