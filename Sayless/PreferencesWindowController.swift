import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let hostingView = FullSizeHostingView(
            rootView: ContentView()
                .environmentObject(appModel)
                .ignoresSafeArea()
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let glassContainer = PreferencesGlassContainerView()
        glassContainer.material = .underWindowBackground
        glassContainer.blendingMode = .behindWindow
        glassContainer.state = .followsWindowActiveState
        glassContainer.wantsLayer = true
        glassContainer.layer?.backgroundColor = NSColor.clear.cgColor
        glassContainer.layer?.cornerRadius = WindowStyling.preferencesCornerRadius
        glassContainer.layer?.cornerCurve = .continuous
        glassContainer.layer?.masksToBounds = true
        glassContainer.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassContainer.bottomAnchor)
        ])

        window.contentView = glassContainer
        WindowStyling.applyPreferencesGlass(to: window)
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        guard let window else {
            return
        }

        if !window.isVisible {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class FullSizeHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

private final class PreferencesGlassContainerView: NSVisualEffectView {
    override func layout() {
        super.layout()

        if let window {
            WindowStyling.layoutPreferencesTrafficLights(in: window)
        }
    }
}
