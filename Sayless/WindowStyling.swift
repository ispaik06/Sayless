import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

enum WindowStyling {
    static let preferencesCornerRadius: CGFloat = 30
    private static let trafficLightLeadingInset: CGFloat = 22
    private static let trafficLightTopInset: CGFloat = 22
    private static let trafficLightButtonGap: CGFloat = 8

    static func applyPreferencesGlass(to window: NSWindow) {
        window.title = "Sayless Preferences"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .documentWindow
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.toolbarStyle = .unified
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 560, height: 520)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = preferencesCornerRadius
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }

        DispatchQueue.main.async {
            installPreferencesTrafficLights(in: window)
            layoutPreferencesTrafficLights(in: window)
        }

        window.invalidateShadow()
    }

    private static func installPreferencesTrafficLights(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        guard buttons.count == 3 else {
            return
        }

        for button in buttons {
            button.isHidden = false
        }
    }

    static func layoutPreferencesTrafficLights(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        guard buttons.count == 3, let contentView = window.contentView else {
            return
        }

        var nextX = trafficLightLeadingInset

        for button in buttons {
            button.isHidden = false

            guard let buttonSuperview = button.superview else {
                continue
            }

            let contentFrame = CGRect(
                x: nextX,
                y: contentView.isFlipped
                    ? trafficLightTopInset
                    : contentView.bounds.height - trafficLightTopInset - button.frame.height,
                width: button.frame.width,
                height: button.frame.height
            )

            button.frame = buttonSuperview.convert(contentFrame, from: contentView).integral
            nextX += button.frame.width + trafficLightButtonGap
        }
    }

}
