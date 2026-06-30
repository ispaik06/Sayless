import Foundation
import Combine

struct Suggestion: Identifiable {
    let id = UUID()
    let label: String
    let text: String
}

struct SuggestionBatch: Identifiable {
    let id = UUID()
    let intent: SuggestionIntent
    let suggestions: [Suggestion]
}

enum SuggestionIntent: Equatable {
    case initial
    case refresh(Int)
    case regenerate
    case shorter
    case softer
    case wittier
    case custom(String)

    var backendKind: String {
        switch self {
        case .initial: "initial"
        case .refresh: "refresh"
        case .regenerate: "regenerate"
        case .shorter: "shorter"
        case .softer: "softer"
        case .wittier: "wittier"
        case .custom: "custom"
        }
    }

    var refreshIndex: Int? {
        if case .refresh(let index) = self {
            return max(index, 1)
        }

        return nil
    }

    var isRefreshRequest: Bool {
        switch self {
        case .refresh(_), .regenerate:
            return true
        case .initial, .shorter, .softer, .wittier, .custom:
            return false
        }
    }

    var instruction: String? {
        if case .custom(let instruction) = self {
            return instruction
        }

        return nil
    }
}

enum SuggestionAdjustmentOption: CaseIterable, Equatable, Hashable, Identifiable {
    case styleSlotOne
    case styleSlotTwo
    case styleSlotThree
    case custom

    var id: String {
        switch self {
        case .styleSlotOne: "styleSlotOne"
        case .styleSlotTwo: "styleSlotTwo"
        case .styleSlotThree: "styleSlotThree"
        case .custom: "custom"
        }
    }

    var styleSlotIndex: Int? {
        switch self {
        case .styleSlotOne: 0
        case .styleSlotTwo: 1
        case .styleSlotThree: 2
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .styleSlotOne, .styleSlotTwo, .styleSlotThree:
            ReplyStyleSettings.shared.preset(for: self)?.title ?? "스타일"
        case .custom: "직접 입력"
        }
    }

    var systemImage: String {
        switch self {
        case .styleSlotOne, .styleSlotTwo, .styleSlotThree:
            ReplyStyleSettings.shared.preset(for: self)?.systemImage ?? "slider.horizontal.3"
        case .custom: "keyboard"
        }
    }

    var intent: SuggestionIntent? {
        switch self {
        case .styleSlotOne, .styleSlotTwo, .styleSlotThree:
            guard let preset = ReplyStyleSettings.shared.preset(for: self) else {
                return nil
            }

            return .custom("Transform the current replies using this style preset: \(preset.title). \(preset.instruction)")
        case .custom:
            return nil
        }
    }
}

enum OverlayKeyboardFocus {
    case suggestions
    case adjustments
}

enum OverlayContent {
    case generating(context: FocusedTextContext)
    case generationFailed(context: FocusedTextContext, message: String?)
    case suggestions(context: FocusedTextContext, batches: [SuggestionBatch], activeBatchIndex: Int)
    case notice(title: String, message: String, buttonTitle: String?)

    var focusedContext: FocusedTextContext? {
        switch self {
        case .generating(let context), .generationFailed(let context, _):
            return context
        case .suggestions(let context, _, _):
            return context
        case .notice:
            return nil
        }
    }

    var suggestionBatches: [SuggestionBatch] {
        if case .suggestions(_, let batches, _) = self {
            return batches
        }

        return []
    }

    var activeBatchIndex: Int? {
        if case .suggestions(_, let batches, let activeBatchIndex) = self, !batches.isEmpty {
            return min(max(activeBatchIndex, 0), batches.count - 1)
        }

        return nil
    }

    var activeSuggestions: [Suggestion] {
        guard let activeBatchIndex else {
            return []
        }

        return suggestionBatches[activeBatchIndex].suggestions
    }

    var displayTitle: String? {
        switch self {
        case .generating(let context), .generationFailed(let context, _):
            return context.windowTitle
        case .suggestions(let context, _, _):
            return context.windowTitle
        case .notice:
            return nil
        }
    }
}

final class OverlayState: ObservableObject {
    @Published var content: OverlayContent = .notice(title: "", message: "", buttonTitle: nil)
    @Published var keyboardFocus: OverlayKeyboardFocus = .suggestions
    @Published var selectedIndex: Int?
    @Published var selectedAdjustmentIndex: Int?
    @Published var isGeneratingMore = false
    @Published var hasNewerVisibleMessages = false
    @Published var isCustomInstructionVisible = false
    @Published var isCustomInstructionFocused = false
    @Published var customInstructionDraft = ""
    @Published var refreshShortcutTitle = "⌘ R"
    @Published var isPresented = false
    @Published var isDismissing = false

    func update(content: OverlayContent) {
        self.content = content
        selectedIndex = content.activeSuggestions.isEmpty ? nil : 0
        keyboardFocus = .suggestions
        selectedAdjustmentIndex = nil
        isGeneratingMore = false
    }
}
