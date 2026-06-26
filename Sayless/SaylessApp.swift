//
//  SaylessApp.swift
//  Sayless
//
//  Created by IN-SEONG PAIK on 6/25/26.
//

import SwiftUI

@main
struct SaylessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("Sayless", systemImage: appModel.menuBarIconOption.systemImage) {
            Button("Show Sayless") {
                appModel.handleSummon()
            }

            Button("Check Accessibility") {
                appModel.checkAccessibilityFromMenu()
            }

            SettingsLink {
                Text("Preferences...")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
