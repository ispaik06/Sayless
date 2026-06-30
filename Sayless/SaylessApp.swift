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
    @StateObject private var languageSettings = AppLanguageSettings.shared
    @StateObject private var updateManager = UpdateManager.shared

    var body: some Scene {
        MenuBarExtra("Sayless", systemImage: appModel.menuBarIconOption.systemImage) {
            Button(languageSettings.text("Home", "홈")) {
                appModel.openHome()
            }

            Button(languageSettings.text("Check Accessibility", "손쉬운 사용 권한 확인")) {
                appModel.checkAccessibilityFromMenu()
            }

            Button(languageSettings.text("Check for Updates...", "업데이트 확인...")) {
                updateManager.checkForUpdates()
            }

            Divider()

            Button(languageSettings.text("Quit", "종료")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
