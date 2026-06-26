import Foundation
import Combine

struct Suggestion: Identifiable {
    let id = UUID()
    let label: String
    let text: String

    static let fixed: [Suggestion] = [
        Suggestion(label: "가볍게", text: "오 좋아. 어디서 볼 건데?"),
        Suggestion(label: "살짝 플러팅", text: "너가 보자고 하면 시간 만들어야지 ㅋㅋ"),
        Suggestion(label: "부담 없이", text: "잠깐은 괜찮을 듯!")
    ]
}

struct SuggestionBatch: Identifiable {
    let id = UUID()
    let intent: SuggestionIntent
    let suggestions: [Suggestion]
}

enum SuggestionIntent: Equatable {
    case initial
    case regenerate
    case shorter
    case softer
    case wittier
    case custom(String)

    var backendKind: String {
        switch self {
        case .initial: "initial"
        case .regenerate: "regenerate"
        case .shorter: "shorter"
        case .softer: "softer"
        case .wittier: "wittier"
        case .custom: "custom"
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
    case shorter
    case softer
    case wittier
    case custom

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .shorter: "더 짧게"
        case .softer: "더 부드럽게"
        case .wittier: "더 센스있게"
        case .custom: "직접 입력"
        }
    }

    var systemImage: String {
        switch self {
        case .shorter: "textformat.size.smaller"
        case .softer: "leaf"
        case .wittier: "sparkles"
        case .custom: "keyboard"
        }
    }

    var intent: SuggestionIntent? {
        switch self {
        case .shorter: .shorter
        case .softer: .softer
        case .wittier: .wittier
        case .custom: nil
        }
    }
}

enum OverlayKeyboardFocus {
    case suggestions
    case adjustments
}

enum OverlayContent {
    case generating(context: FocusedTextContext)
    case generationFailed(context: FocusedTextContext)
    case suggestions(context: FocusedTextContext, batches: [SuggestionBatch], activeBatchIndex: Int)
    case notice(title: String, message: String, buttonTitle: String?)

    var focusedContext: FocusedTextContext? {
        switch self {
        case .generating(let context), .generationFailed(let context):
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
}

final class OverlayState: ObservableObject {
    @Published var content: OverlayContent = .notice(title: "", message: "", buttonTitle: nil)
    @Published var keyboardFocus: OverlayKeyboardFocus = .suggestions
    @Published var selectedIndex: Int?
    @Published var selectedAdjustmentIndex: Int?
    @Published var usedAdjustmentOptions: Set<SuggestionAdjustmentOption> = []
    @Published var isGeneratingMore = false
    @Published var hasNewerVisibleMessages = false
    @Published var isCustomInstructionVisible = false
    @Published var isCustomInstructionFocused = false
    @Published var customInstructionDraft = ""
    @Published var refreshShortcutTitle = "⌘ R"

    func update(content: OverlayContent) {
        self.content = content
        selectedIndex = content.activeSuggestions.isEmpty ? nil : 0
        keyboardFocus = .suggestions
        selectedAdjustmentIndex = nil
        isGeneratingMore = false
    }
}
