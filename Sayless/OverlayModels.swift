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

enum OverlayContent {
    case generating(context: FocusedTextContext)
    case generationFailed(context: FocusedTextContext)
    case suggestions(context: FocusedTextContext, items: [Suggestion])
    case notice(title: String, message: String, buttonTitle: String?)

    var focusedContext: FocusedTextContext? {
        switch self {
        case .generating(let context), .generationFailed(let context):
            return context
        case .suggestions(let context, _):
            return context
        case .notice:
            return nil
        }
    }
}

final class OverlayState: ObservableObject {
    @Published var content: OverlayContent = .notice(title: "", message: "", buttonTitle: nil)
    @Published var selectedIndex: Int?

    func update(content: OverlayContent) {
        self.content = content
        selectedIndex = nil
    }
}
