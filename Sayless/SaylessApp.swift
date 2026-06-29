//
//  SaylessApp.swift
//  Sayless
//
//  Created by IN-SEONG PAIK on 6/25/26.
//

import ClerkKit
import SwiftUI

@main
struct SaylessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var authSession = AuthSessionManager.shared
    @StateObject private var updateManager = UpdateManager.shared

    var body: some Scene {
        MenuBarExtra("Sayless", systemImage: appModel.menuBarIconOption.systemImage) {
            Button("Show Sayless") {
                appModel.handleSummon()
            }

            Button("Check Accessibility") {
                appModel.checkAccessibilityFromMenu()
            }

            Button("Preferences...") {
                appModel.openPreferences()
            }

            Button("Check for Updates...") {
                updateManager.checkForUpdates()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .environment(authSession.clerk)
    }
}
