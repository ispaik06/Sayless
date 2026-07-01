import AppKit
import ApplicationServices
import SwiftUI

final class OverlayPanelController {
    enum Placement {
        case automatic
        case centered
    }

    private var panel: KeyHandlingPanel?
    private let insertionService = TextInsertionService()
    private let accessibilityReader = AccessibilityReader()
    private let state = OverlayState()
    private var displayGeneration = 0
    private var sourceWindowMonitor: Timer?
    private var latestMessageSignature: ChatTimelineSignature?
    private var latestMessageCheckTime: CFAbsoluteTime = 0
    var onSuggestionGenerationRequested: ((FocusedTextContext, SuggestionIntent) -> Void)?
    var onContextResetRequested: ((FocusedTextContext) -> Void)?
    var onSuggestionAccepted: (() -> Void)?
    var onSourceWindowInvalidated: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var currentFocusedContext: FocusedTextContext? {
        state.content.focusedContext
    }

    var suggestionHistory: [Suggestion] {
        state.content.suggestionBatches.flatMap(\.suggestions)
    }

    var suggestionBatches: [SuggestionBatch] {
        state.content.suggestionBatches
    }

    var activeSuggestions: [Suggestion] {
        state.content.activeSuggestions
    }

    @discardableResult
    func show(content: OverlayContent, near axFrame: CGRect?) -> Int {
        show(content: content, near: axFrame, placement: .automatic)
    }

    @discardableResult
    func refresh(content: OverlayContent) -> Int {
        displayGeneration += 1
        state.update(content: content)
        relayoutPanel(for: content, animated: false)
        startSourceWindowMonitor(for: content)
        return displayGeneration
    }

    @discardableResult
    func showSuggestions(
        context: FocusedTextContext,
        batches: [SuggestionBatch],
        near axFrame: CGRect?
    ) -> Int {
        show(
            content: .suggestions(
                context: context,
                batches: batches,
                activeBatchIndex: max(batches.count - 1, 0)
            ),
            near: axFrame
        )
    }

    @discardableResult
    func beginSuggestionRequest() -> Int {
        state.isGeneratingMore = true
        return displayGeneration
    }

    func appendSuggestions(_ batch: SuggestionBatch, context: FocusedTextContext, for generation: Int) {
        guard displayGeneration == generation,
              isVisible else {
            return
        }

        let currentBatches = state.content.suggestionBatches
        let batches = currentBatches + [batch]
        let previousContent = state.content
        state.update(
            content: .suggestions(
                context: context,
                batches: batches,
                activeBatchIndex: batches.count - 1
            )
        )
        if shouldRelayoutAfterAppendingSuggestions(from: previousContent) {
            relayoutPanel(for: state.content, animated: false)
        }
        startSourceWindowMonitor(for: state.content)
    }

    func finishSuggestionRequest() {
        state.isGeneratingMore = false
    }

    func resetSuggestionState() {
        state.hasNewerVisibleMessages = false
        state.keyboardFocus = .suggestions
        state.selectedAdjustmentIndex = nil
        clearCustomInstruction()
        latestMessageSignature = nil
    }

    func update(content: OverlayContent, for generation: Int) {
        update(content: content, for: generation, relayout: true)
    }

    func update(content: OverlayContent, for generation: Int, relayout: Bool) {
        guard displayGeneration == generation,
              isVisible else {
            return
        }

        state.update(content: content)
        if relayout {
            relayoutPanel(for: content, animated: false)
        }
        startSourceWindowMonitor(for: content)
    }

    func showTemporary(
        content: OverlayContent,
        near axFrame: CGRect? = nil,
        placement: Placement = .automatic,
        duration: TimeInterval = 2.2
    ) {
        show(content: content, near: axFrame, placement: placement)
        let generation = displayGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.displayGeneration == generation else {
                return
            }
            self.hide()
        }
    }

    @discardableResult
    private func show(content: OverlayContent, near axFrame: CGRect?, placement: Placement) -> Int {
        displayGeneration += 1
        let generation = displayGeneration
        let panel = makePanelIfNeeded()
        let shouldAnimateAppearance = !panel.isVisible

        if shouldAnimateAppearance {
            state.isDismissing = false
            state.isPresented = false
        }

        state.update(content: content)

        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) == true
        }

        let targetFrame = frameForPanel(content: content, near: axFrame, placement: placement)
        panel.setFrame(targetFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()

        if shouldAnimateAppearance {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.displayGeneration == generation,
                      self.panel?.isVisible == true else {
                    return
                }

                self.state.isPresented = true
            }
        } else {
            state.isPresented = true
        }

        startSourceWindowMonitor(for: content)
        return displayGeneration
    }

    func hide() {
        displayGeneration += 1
        let generation = displayGeneration
        stopSourceWindowMonitor()

        guard let panel,
              panel.isVisible else {
            state.isPresented = false
            state.isDismissing = false
            panel?.orderOut(nil)
            return
        }

        state.isDismissing = true
        state.isPresented = false

        DispatchQueue.main.asyncAfter(deadline: .now() + hideAnimationDuration) { [weak self] in
            guard let self,
                  self.displayGeneration == generation else {
                return
            }

            panel.orderOut(nil)
            self.state.isDismissing = false
        }
    }

    private func startSourceWindowMonitor(for content: OverlayContent) {
        stopSourceWindowMonitor()

        guard let context = content.focusedContext,
              let sourceWindow = context.windowElement else {
            return
        }

        let generation = displayGeneration
        latestMessageSignature = nil
        latestMessageCheckTime = CFAbsoluteTimeGetCurrent()
        state.hasNewerVisibleMessages = false

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) {
            let signature = AccessibilityReader().latestVisibleMessageSignature(for: context)

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.displayGeneration == generation,
                      self.isVisible else {
                    return
                }

                self.latestMessageSignature = signature
                self.latestMessageCheckTime = CFAbsoluteTimeGetCurrent()
            }
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
                self.onSourceWindowInvalidated?()
                self.resetSuggestionState()
                self.hide()
                return
            }

            self.detectNewVisibleMessage(for: context)
        }

        sourceWindowMonitor = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func detectNewVisibleMessage(for context: FocusedTextContext) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - latestMessageCheckTime >= 1.0 else {
            return
        }

        latestMessageCheckTime = now

        guard !state.hasNewerVisibleMessages,
              let latestMessageSignature else {
            return
        }

        guard let currentSignature = accessibilityReader.latestVisibleMessageSignature(for: context) else {
            if context.source == .webInstagram {
                onSourceWindowInvalidated?()
                resetSuggestionState()
                hide()
            }
            return
        }

        if context.source == .webInstagram,
           currentSignature != latestMessageSignature,
           !currentSignature.hasMeaningfulOverlap(with: latestMessageSignature) {
            onSourceWindowInvalidated?()
            resetSuggestionState()
            hide()
            return
        }

        if currentSignature.containsNewerMessages(than: latestMessageSignature) {
            state.hasNewerVisibleMessages = true
        }
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
        guard case .suggestions(let context, let batches, let activeBatchIndex) = state.content,
              batches.indices.contains(activeBatchIndex) else {
            return
        }

        let items = batches[activeBatchIndex].suggestions
        let index = state.selectedIndex ?? 0
        guard items.indices.contains(index) else {
            return
        }

        accept(suggestion: items[index], context: context)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if commandShiftRMatches(event) {
            resetContextAndRegenerate()
            return true
        }

        if commandRMatches(event) {
            requestRefreshSuggestions()
            return true
        }

        switch event.keyCode {
        case 53:
            if state.isCustomInstructionFocused {
                state.isCustomInstructionFocused = false
                return true
            }

            hide()
            return true
        case 36, 76:
            if state.isCustomInstructionFocused {
                submitCustomInstruction()
                return true
            }

            if state.keyboardFocus == .adjustments {
                activateSelectedAdjustment()
                return true
            }

            selectCurrentSuggestion()
            return true
        case 48:
            if state.isCustomInstructionFocused {
                return false
            }

            let modifiers = event.modifierFlags.intersection([.control, .shift])
            if modifiers.contains(.control) {
                moveBatch(delta: modifiers.contains(.shift) ? -1 : 1)
            } else {
                moveSelection(delta: modifiers.contains(.shift) ? -1 : 1)
            }
            return true
        case 126:
            if state.isCustomInstructionFocused {
                return false
            }

            if state.keyboardFocus == .adjustments {
                focusSuggestions()
                return true
            }

            return false
        case 125:
            if state.isCustomInstructionVisible, !state.isCustomInstructionFocused {
                state.isCustomInstructionFocused = true
                return true
            }

            if state.keyboardFocus == .suggestions {
                focusAdjustments()
                return true
            }

            return false
        case 123:
            if state.isCustomInstructionFocused {
                return false
            }
            moveAdjustmentFocus(delta: -1)
            return true
        case 124:
            if state.isCustomInstructionFocused {
                return false
            }
            moveAdjustmentFocus(delta: 1)
            return true
        default:
            return false
        }
    }

    private func accept(suggestion: Suggestion, context: FocusedTextContext) {
        insertionService.insert(suggestion.text, into: context)
        onSuggestionAccepted?()
        hide()
    }

    private func moveSelection(delta: Int) {
        guard case .suggestions(let context, let batches, let activeBatchIndex) = state.content,
              !batches.isEmpty else {
            return
        }

        let totalCount = batches.reduce(0) { $0 + $1.suggestions.count }
        guard totalCount > 0 else {
            return
        }

        let currentBatchIndex = min(max(activeBatchIndex, 0), batches.count - 1)
        let currentLocalIndex = state.selectedIndex ?? (delta > 0 ? -1 : 0)
        let currentGlobalIndex = globalIndex(
            batchIndex: currentBatchIndex,
            localIndex: currentLocalIndex,
            batches: batches
        )
        let nextGlobalIndex = (currentGlobalIndex + delta + totalCount) % totalCount
        guard let nextPosition = position(forGlobalIndex: nextGlobalIndex, batches: batches) else {
            return
        }

        state.content = .suggestions(
            context: context,
            batches: batches,
            activeBatchIndex: nextPosition.batchIndex
        )
        state.keyboardFocus = .suggestions
        state.selectedIndex = nextPosition.localIndex
        state.selectedAdjustmentIndex = nil
    }

    private func globalIndex(batchIndex: Int, localIndex: Int, batches: [SuggestionBatch]) -> Int {
        let priorCount = batches.prefix(batchIndex).reduce(0) { $0 + $1.suggestions.count }
        return priorCount + localIndex
    }

    private func position(forGlobalIndex globalIndex: Int, batches: [SuggestionBatch]) -> (batchIndex: Int, localIndex: Int)? {
        var remaining = globalIndex

        for batchIndex in batches.indices {
            let count = batches[batchIndex].suggestions.count
            if remaining < count {
                return (batchIndex, remaining)
            }

            remaining -= count
        }

        return nil
    }

    private func moveBatch(delta: Int) {
        guard case .suggestions(let context, let batches, let activeBatchIndex) = state.content,
              !batches.isEmpty else {
            return
        }

        let nextBatchIndex = (activeBatchIndex + delta + batches.count) % batches.count
        state.content = .suggestions(
            context: context,
            batches: batches,
            activeBatchIndex: nextBatchIndex
        )
        state.keyboardFocus = .suggestions
        state.selectedIndex = 0
        state.selectedAdjustmentIndex = nil
    }

    private func focusSuggestions() {
        guard !state.content.activeSuggestions.isEmpty else {
            return
        }

        state.keyboardFocus = .suggestions
        state.selectedIndex = state.selectedIndex ?? 0
        state.selectedAdjustmentIndex = nil
    }

    private func focusAdjustments() {
        guard let index = nextAvailableAdjustmentIndex(from: nil, delta: 1) else {
            return
        }

        state.keyboardFocus = .adjustments
        state.selectedAdjustmentIndex = index
        hideCustomInstructionIfNeeded(for: SuggestionAdjustmentOption.allCases[index])
    }

    private func moveAdjustmentFocus(delta: Int) {
        guard let nextIndex = nextAvailableAdjustmentIndex(
            from: state.keyboardFocus == .adjustments ? state.selectedAdjustmentIndex : nil,
            delta: delta
        ) else {
            return
        }

        state.keyboardFocus = .adjustments
        state.selectedAdjustmentIndex = nextIndex
        hideCustomInstructionIfNeeded(for: SuggestionAdjustmentOption.allCases[nextIndex])
    }

    private func nextAvailableAdjustmentIndex(from currentIndex: Int?, delta: Int) -> Int? {
        let options = SuggestionAdjustmentOption.allCases
        guard !options.isEmpty else {
            return nil
        }

        let step = delta >= 0 ? 1 : -1
        let startIndex: Int
        if let currentIndex,
           options.indices.contains(currentIndex) {
            startIndex = currentIndex
        } else {
            startIndex = step > 0 ? -1 : options.count
        }

        return (startIndex + step + (options.count * 2)) % options.count
    }

    private func activateSelectedAdjustment() {
        let options = SuggestionAdjustmentOption.allCases
        guard let selectedAdjustmentIndex = state.selectedAdjustmentIndex,
              options.indices.contains(selectedAdjustmentIndex) else {
            focusAdjustments()
            return
        }

        activateAdjustment(options[selectedAdjustmentIndex])
    }

    private func activateAdjustment(_ option: SuggestionAdjustmentOption) {
        guard !state.isGeneratingMore else {
            return
        }

        state.keyboardFocus = .adjustments
        state.selectedAdjustmentIndex = SuggestionAdjustmentOption.allCases.firstIndex(of: option)

        if option == .custom {
            state.isCustomInstructionVisible = true
            relayoutPanel(for: state.content, animated: false)
            state.isCustomInstructionFocused = true
            return
        }

        clearCustomInstruction()

        guard let intent = option.intent else {
            return
        }

        requestSuggestions(intent: intent)
    }

    private func submitCustomInstruction() {
        let instruction = state.customInstructionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty,
              !state.isGeneratingMore else {
            return
        }

        clearCustomInstruction()
        requestSuggestions(intent: .custom(instruction))
    }

    private func hideCustomInstructionIfNeeded(for option: SuggestionAdjustmentOption) {
        if option != .custom {
            clearCustomInstruction()
        }
    }

    private func clearCustomInstruction() {
        let wasVisible = state.isCustomInstructionVisible
        state.isCustomInstructionVisible = false
        state.isCustomInstructionFocused = false
        state.customInstructionDraft = ""

        if wasVisible {
            relayoutPanel(for: state.content, animated: false)
        }
    }

    private func requestSuggestions(intent: SuggestionIntent) {
        guard let context = state.content.focusedContext else {
            return
        }

        state.isGeneratingMore = true
        onSuggestionGenerationRequested?(context, intent)
    }

    private func requestRefreshSuggestions() {
        requestSuggestions(intent: .refresh(nextRefreshIndex()))
    }

    private func nextRefreshIndex() -> Int {
        state.content.suggestionBatches.filter { $0.intent.isRefreshRequest }.count + 1
    }

    private func commandRMatches(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return event.keyCode == 15 && modifiers == .command
    }

    private func commandShiftRMatches(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return event.keyCode == 15 && modifiers == [.command, .shift]
    }

    private func resetContextAndRegenerate() {
        guard let context = state.content.focusedContext else {
            return
        }

        resetSuggestionState()
        onContextResetRequested?(context)
    }

    private func makePanelIfNeeded() -> KeyHandlingPanel {
        if let panel {
            return panel
        }

        let panel = KeyHandlingPanel(
            contentRect: CGRect(x: 0, y: 0, width: 470, height: 342),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = DraggableHostingView(
            rootView: SaylessOverlayView(
                state: state,
                onSelect: { [weak self] suggestion, context in
                    self?.accept(suggestion: suggestion, context: context)
                },
                onClose: { [weak self] in
                    self?.hide()
                },
                onRefresh: { [weak self] in
                    self?.requestRefreshSuggestions()
                },
                onAdjustment: { [weak self] option in
                    self?.activateAdjustment(option)
                },
                onCustomInstructionSubmit: { [weak self] in
                    self?.submitCustomInstruction()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = false
        panel.invalidateShadow()
        self.panel = panel
        return panel
    }

    private func relayoutPanel(for content: OverlayContent, animated: Bool) {
        guard let panel,
              panel.isVisible else {
            return
        }

        let targetFrame = frameForPanel(content: content, near: content.focusedContext?.frame)
        panel.setFrame(targetFrame, display: true, animate: animated)
    }

    private func shouldRelayoutAfterAppendingSuggestions(from previousContent: OverlayContent) -> Bool {
        switch previousContent {
        case .generating:
            return hasComposingPreview(state.content)
        case .generationFailed, .suggestions, .notice:
            return true
        }
    }

    private func frameForPanel(content: OverlayContent, near axFrame: CGRect?, placement: Placement = .automatic) -> CGRect {
        let size = panelSize(for: content)
        let windowFrame: CGRect?
        windowFrame = content.focusedContext?.windowFrame
        let screenSeedFrame = windowFrame ?? axFrame
        let targetScreen = screen(for: screenSeedFrame) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? .zero
        let screenFrame = targetScreen?.frame ?? visibleFrame

        if let inputFrame = axFrame.map({ cocoaFrame(fromAXFrame: $0, screenFrame: screenFrame) }) {
            return bestSuggestionFrame(size: size, inputFrame: inputFrame, visibleFrame: visibleFrame)
        }

        let cocoaWindowFrame = windowFrame.map { cocoaFrame(fromAXFrame: $0, screenFrame: screenFrame) }
        let anchorFrame = cocoaWindowFrame ?? visibleFrame

        if placement == .centered {
            return centeredFloatingFrame(size: size, anchorFrame: visibleFrame, visibleFrame: visibleFrame)
        }

        if axFrame == nil,
           isUpperFloatingContent(content) {
            return upperFloatingFrame(size: size, visibleFrame: visibleFrame)
        }

        return centeredFloatingFrame(size: size, anchorFrame: anchorFrame, visibleFrame: visibleFrame)
    }

    private func isUpperFloatingContent(_ content: OverlayContent) -> Bool {
        switch content {
        case .notice:
            return true
        case .generating, .generationFailed, .suggestions:
            return false
        }
    }

    private var hideAnimationDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.14
    }

    private func centeredFloatingFrame(size: CGSize, anchorFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 18
        let safeFrame = visibleFrame.insetBy(dx: margin, dy: margin)
        let usableAnchor = anchorFrame.intersection(visibleFrame).isNull
            ? visibleFrame
            : anchorFrame.intersection(visibleFrame)
        let topBias = min(max(usableAnchor.height * 0.14, 46), 96)
        let x = clamp(usableAnchor.midX - size.width / 2, min: safeFrame.minX, max: safeFrame.maxX - size.width)
        let y = clamp(usableAnchor.midY - size.height / 2 + topBias, min: safeFrame.minY, max: safeFrame.maxY - size.height)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func upperFloatingFrame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 18
        let safeFrame = visibleFrame.insetBy(dx: margin, dy: margin)
        let topGap = min(max(visibleFrame.height * 0.10, 64), 108)
        let x = clamp(visibleFrame.midX - size.width / 2, min: safeFrame.minX, max: safeFrame.maxX - size.width)
        let y = clamp(visibleFrame.maxY - size.height - topGap, min: safeFrame.minY, max: safeFrame.maxY - size.height)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func bestSuggestionFrame(
        size: CGSize,
        inputFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let margin: CGFloat = 8
        let placementArea = visibleFrame.insetBy(dx: margin, dy: margin)

        let rightSpace = placementArea.maxX - inputFrame.maxX - margin
        let leftSpace = inputFrame.minX - placementArea.minX - margin
        let belowSpace = inputFrame.minY - placementArea.minY - margin
        let aboveSpace = placementArea.maxY - inputFrame.maxY - margin

        var orderedCandidates: [CGRect] = []

        if belowSpace >= size.height * 0.82 {
            let belowGap: CGFloat = 8
            let x = clamp(inputFrame.minX, min: placementArea.minX, max: placementArea.maxX - size.width)
            let y = max(inputFrame.minY - size.height - belowGap, placementArea.minY)
            orderedCandidates.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
        }

        if rightSpace >= size.width {
            let x = inputFrame.maxX + margin
            let y = clamp(inputFrame.midY - size.height + 14, min: placementArea.minY, max: placementArea.maxY - size.height)
            orderedCandidates.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
        }

        if leftSpace >= size.width {
            let x = inputFrame.minX - size.width - margin
            let y = clamp(inputFrame.midY - size.height + 14, min: placementArea.minY, max: placementArea.maxY - size.height)
            orderedCandidates.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
        }

        if aboveSpace >= size.height {
            let x = clamp(inputFrame.maxX - size.width, min: placementArea.minX, max: placementArea.maxX - size.width)
            let y = inputFrame.maxY + 8
            orderedCandidates.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
        }

        if let frame = orderedCandidates.first(where: { placementArea.contains($0) }) {
            return frame
        }

        let fallback = fallbackFrame(size: size, inputFrame: inputFrame, visibleFrame: visibleFrame)
        return fallback
    }

    private func fallbackFrame(size: CGSize, inputFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 8
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
        case .generating, .generationFailed:
            return CGSize(width: 470, height: 342)
        case .suggestions:
            let previewHeight: CGFloat = hasComposingPreview(content) ? 58 : 0
            let customInputHeight: CGFloat = state.isCustomInstructionVisible ? 44 : 0
            return CGSize(width: 470, height: 342 + previewHeight + customInputHeight)
        case .notice(_, _, let buttonTitle):
            return buttonTitle == nil ? CGSize(width: 470, height: 118) : CGSize(width: 470, height: 248)
        }
    }

    private func hasComposingPreview(_ content: OverlayContent) -> Bool {
        let draft = content.focusedContext?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !draft.isEmpty
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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           keyHandler?(event) == true {
            return
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
