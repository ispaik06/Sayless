import AppKit
import ApplicationServices
import SwiftUI

final class OverlayPanelController {
    private var panel: KeyHandlingPanel?
    private let insertionService = TextInsertionService()
    private let state = OverlayState()
    private var displayGeneration = 0
    private var sourceWindowMonitor: Timer?
    var onRefreshRequested: ((FocusedTextContext) -> Void)?
    var onSuggestionAccepted: (() -> Void)?
    private var refreshShortcutOption: RefreshShortcutOption = .rightArrow
    private var customRefreshShortcut: KeyboardShortcutSpec?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var currentFocusedContext: FocusedTextContext? {
        state.content.focusedContext
    }

    func configureRefreshShortcut(_ option: RefreshShortcutOption, customShortcut: KeyboardShortcutSpec?) {
        refreshShortcutOption = option
        customRefreshShortcut = customShortcut
        state.refreshShortcutTitle = refreshShortcutTitle
    }

    @discardableResult
    func show(content: OverlayContent, near axFrame: CGRect?) -> Int {
        displayGeneration += 1
        state.update(content: content)

        let panel = makePanelIfNeeded()
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) == true
        }

        let targetFrame = frameForPanel(content: content, near: axFrame)
        panel.setFrame(targetFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        startSourceWindowMonitor(for: content)
        return displayGeneration
    }

    @discardableResult
    func refresh(content: OverlayContent) -> Int {
        displayGeneration += 1
        state.update(content: content)
        startSourceWindowMonitor(for: content)
        return displayGeneration
    }

    func update(content: OverlayContent, for generation: Int) {
        guard displayGeneration == generation,
              isVisible else {
            return
        }

        state.update(content: content)
        startSourceWindowMonitor(for: content)
    }

    func showTemporary(content: OverlayContent, near axFrame: CGRect? = nil, duration: TimeInterval = 2.2) {
        show(content: content, near: axFrame)
        let generation = displayGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.displayGeneration == generation else {
                return
            }
            self.hide()
        }
    }

    func hide() {
        displayGeneration += 1
        stopSourceWindowMonitor()
        panel?.orderOut(nil)
    }

    private func startSourceWindowMonitor(for content: OverlayContent) {
        stopSourceWindowMonitor()

        guard let context = content.focusedContext,
              let sourceWindow = context.windowElement else {
            return
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            guard self.isVisible else {
                self.stopSourceWindowMonitor()
                return
            }

            if !self.isSourceWindowUsable(sourceWindow) {
                self.hide()
            }
        }

        sourceWindowMonitor = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSourceWindowMonitor() {
        sourceWindowMonitor?.invalidate()
        sourceWindowMonitor = nil
    }

    private func isSourceWindowUsable(_ window: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
        guard roleResult == .success,
              (roleValue as? String) == kAXWindowRole as String else {
            return false
        }

        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
           let minimized = minimizedValue as? Bool,
           minimized {
            return false
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success
            && AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
    }

    private func selectCurrentSuggestion() {
        guard case .suggestions(let context, let items) = state.content else {
            return
        }

        let index = state.selectedIndex ?? 0
        guard items.indices.contains(index) else {
            return
        }

        insertionService.insert(items[index].text, into: context)
        onSuggestionAccepted?()
        hide()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if refreshShortcutMatches(event),
           let context = state.content.focusedContext {
            onRefreshRequested?(context)
            return true
        }

        switch event.keyCode {
        case 53:
            hide()
            return true
        case 36, 76:
            selectCurrentSuggestion()
            return true
        case 125:
            moveSelection(delta: 1)
            return true
        case 126:
            moveSelection(delta: -1)
            return true
        default:
            return false
        }
    }

    private func moveSelection(delta: Int) {
        guard case .suggestions(_, let items) = state.content, !items.isEmpty else {
            return
        }

        if let selectedIndex = state.selectedIndex {
            state.selectedIndex = (selectedIndex + delta + items.count) % items.count
        } else {
            state.selectedIndex = delta > 0 ? 0 : items.count - 1
        }
    }

    private func refreshShortcutMatches(_ event: NSEvent) -> Bool {
        if refreshShortcutOption == .custom {
            return customRefreshShortcut?.matches(event) == true
        }

        return refreshShortcutOption.matches(event)
    }

    private var refreshShortcutTitle: String {
        if refreshShortcutOption == .custom {
            return customRefreshShortcut?.title ?? "Custom"
        }

        return refreshShortcutOption.title
    }

    private func makePanelIfNeeded() -> KeyHandlingPanel {
        if let panel {
            return panel
        }

        let panel = KeyHandlingPanel(
            contentRect: CGRect(x: 0, y: 0, width: 430, height: 236),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = DraggableHostingView(
            rootView: SaylessOverlayView(
                state: state,
                onSelect: { [weak self] suggestion, context in
                    self?.insertionService.insert(suggestion.text, into: context)
                    self?.onSuggestionAccepted?()
                    self?.hide()
                },
                onClose: { [weak self] in
                    self?.hide()
                },
                onRefresh: { [weak self] in
                    guard let context = self?.state.content.focusedContext else {
                        return
                    }
                    self?.onRefreshRequested?(context)
                }
            )
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }

    private func frameForPanel(content: OverlayContent, near axFrame: CGRect?) -> CGRect {
        let size = panelSize(for: content)
        let windowFrame: CGRect?
        windowFrame = content.focusedContext?.windowFrame
        let screenSeedFrame = windowFrame ?? axFrame
        let targetScreen = screen(for: screenSeedFrame) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? .zero
        let screenFrame = targetScreen?.frame ?? visibleFrame

        guard let axFrame else {
            return CGRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - 86,
                width: size.width,
                height: size.height
            )
        }

        let inputFrame = cocoaFrame(fromAXFrame: axFrame, screenFrame: screenFrame)
        let cocoaWindowFrame = windowFrame.map { cocoaFrame(fromAXFrame: $0, screenFrame: screenFrame) }

        if let cocoaWindowFrame {
            return bestSuggestionFrame(
                size: size,
                inputFrame: inputFrame,
                windowFrame: cocoaWindowFrame,
                visibleFrame: visibleFrame
            )
        } else {
            return fallbackFrame(size: size, inputFrame: inputFrame, visibleFrame: visibleFrame)
        }
    }

    private func bestSuggestionFrame(
        size: CGSize,
        inputFrame: CGRect,
        windowFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let margin: CGFloat = 12
        let placementArea = visibleFrame.insetBy(dx: margin, dy: margin)

        let rightSpace = placementArea.maxX - inputFrame.maxX - margin
        let leftSpace = inputFrame.minX - placementArea.minX - margin
        let belowSpace = inputFrame.minY - placementArea.minY - margin
        let aboveSpace = placementArea.maxY - inputFrame.maxY - margin

        var candidates: [(frame: CGRect, score: CGFloat, name: String)] = []

        if rightSpace >= size.width * 0.72 {
            let x = min(inputFrame.maxX + margin, placementArea.maxX - size.width)
            let y = clamp(inputFrame.midY - size.height + 34, min: placementArea.minY, max: placementArea.maxY - size.height)
            candidates.append((CGRect(origin: CGPoint(x: x, y: y), size: size), rightSpace + 1000, "right"))
        }

        if belowSpace >= min(size.height * 0.72, 120) {
            let x = clamp(inputFrame.minX, min: placementArea.minX, max: placementArea.maxX - size.width)
            let y = max(inputFrame.minY - size.height - margin, placementArea.minY)
            candidates.append((CGRect(origin: CGPoint(x: x, y: y), size: size), belowSpace + 700, "below-input"))
        }

        if aboveSpace >= size.height * 0.74 {
            let x = clamp(inputFrame.maxX - size.width, min: placementArea.minX, max: placementArea.maxX - size.width)
            let y = min(inputFrame.maxY + margin, placementArea.maxY - size.height)
            candidates.append((CGRect(origin: CGPoint(x: x, y: y), size: size), aboveSpace + 500, "above-input"))
        }

        if leftSpace >= size.width * 0.72 {
            let x = max(inputFrame.minX - size.width - margin, placementArea.minX)
            let y = clamp(inputFrame.midY - size.height + 34, min: placementArea.minY, max: placementArea.maxY - size.height)
            candidates.append((CGRect(origin: CGPoint(x: x, y: y), size: size), leftSpace + 100, "left"))
        }

        if let best = candidates.max(by: { $0.score < $1.score }) {
            return best.frame
        }

        let fallback = fallbackFrame(size: size, inputFrame: inputFrame, visibleFrame: visibleFrame)
        return fallback
    }

    private func fallbackFrame(size: CGSize, inputFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let safeFrame = visibleFrame.insetBy(dx: margin, dy: margin)

        var x = inputFrame.minX
        var y = inputFrame.minY - size.height - margin

        if y < safeFrame.minY {
            y = inputFrame.maxY + margin
        }

        x = clamp(x, min: safeFrame.minX, max: safeFrame.maxX - size.width)
        y = clamp(y, min: safeFrame.minY, max: safeFrame.maxY - size.height)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }

        return Swift.min(Swift.max(value, minimum), maximum)
    }

    private func panelSize(for content: OverlayContent) -> CGSize {
        switch content {
        case .generating, .generationFailed, .suggestions:
            CGSize(width: 430, height: 258)
        case .notice(_, _, let buttonTitle):
            buttonTitle == nil ? CGSize(width: 330, height: 118) : CGSize(width: 430, height: 248)
        }
    }

    private func screen(for axFrame: CGRect?) -> NSScreen? {
        guard let axFrame else {
            return NSScreen.main
        }

        let point = axFrame.origin
        return NSScreen.screens.first { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x <= frame.maxX
        } ?? NSScreen.main
    }

    private func cocoaFrame(fromAXFrame frame: CGRect, screenFrame: CGRect) -> CGRect {
        let y = screenFrame.maxY - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
    }
}

final class KeyHandlingPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
