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

        guard buttons.count == 3, let contentView = window.contentView else {
            return
        }

        let titlebarButtonSuperview = buttons.first?.superview === contentView ? nil : buttons.first?.superview

        for button in buttons {
            if button.superview !== contentView {
                button.removeFromSuperview()
                contentView.addSubview(button)
            }

            button.autoresizingMask = [.maxXMargin, .minYMargin]
            button.isHidden = false
        }

        titlebarButtonSuperview?.isHidden = true
        hideTitlebarChrome(in: window, preserving: contentView)
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
            var frame = button.frame
            frame.origin.x = nextX

            if contentView.isFlipped {
                frame.origin.y = trafficLightTopInset
            } else {
                frame.origin.y = contentView.bounds.height - trafficLightTopInset - frame.height
            }

            button.frame = frame.integral
            nextX += frame.width + trafficLightButtonGap
        }
    }

    private static func hideTitlebarChrome(in window: NSWindow, preserving contentView: NSView) {
        guard let frameView = contentView.superview else {
            return
        }

        hideTitlebarChrome(in: frameView, preserving: contentView)
    }

    private static func hideTitlebarChrome(in view: NSView, preserving preservedView: NSView) {
        for subview in view.subviews {
            if subview === preservedView || subview.isDescendant(of: preservedView) {
                continue
            }

            let className = NSStringFromClass(type(of: subview)).lowercased()
            let isTitlebarChrome = className.contains("titlebar")
                || className.contains("toolbar")
                || className.contains("separator")

            if isTitlebarChrome {
                subview.isHidden = true
                subview.alphaValue = 0
            } else {
                hideTitlebarChrome(in: subview, preserving: preservedView)
            }
        }
    }
}
