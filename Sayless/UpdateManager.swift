import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard automaticallyChecksForUpdates != updaterController.updater.automaticallyChecksForUpdates else {
                return
            }

            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    let isUsingPlaceholderPublicKey: Bool
    let feedURL: String
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        !isUsingPlaceholderPublicKey && updaterController.updater.canCheckForUpdates
    }

    var appVersionDisplay: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildNumber))"
    }

    private init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        isUsingPlaceholderPublicKey = publicKey == "PLACEHOLDER_PUBLIC_ED_KEY" || publicKey.isEmpty
        self.feedURL = feedURL

        updaterController = SPUStandardUpdaterController(
            startingUpdater: !isUsingPlaceholderPublicKey,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        guard !isUsingPlaceholderPublicKey else {
            showPlaceholderKeyAlert()
            return
        }

        guard updaterController.updater.canCheckForUpdates else {
            NSSound.beep()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private func showPlaceholderKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Updates are not configured yet"
        alert.informativeText = """
        Replace PLACEHOLDER_PUBLIC_ED_KEY with the real Sparkle public EdDSA key before testing or publishing updates.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
