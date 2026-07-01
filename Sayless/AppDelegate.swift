import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        suppressConsoleOutput()
        terminatePreviousInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivationManager.shared.enterMenuBarModeIfPossible()
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

    private func suppressConsoleOutput() {
        freopen("/dev/null", "w", stdout)
        freopen("/dev/null", "w", stderr)
    }
}
