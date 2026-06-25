import Foundation

enum MenuBarIconOption: String, CaseIterable, Identifiable {
    case textBubble
    case quoteBubble
    case chatBubbles
    case wand
    case pencil
    case textCursor
    case keyboard
    case brain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textBubble: "Text Bubble"
        case .quoteBubble: "Quote Bubble"
        case .chatBubbles: "Chat Bubbles"
        case .wand: "Magic Wand"
        case .pencil: "Pencil"
        case .textCursor: "Text Cursor"
        case .keyboard: "Keyboard"
        case .brain: "Brain"
        }
    }

    var systemImage: String {
        switch self {
        case .textBubble: "text.bubble"
        case .quoteBubble: "quote.bubble"
        case .chatBubbles: "bubble.left.and.bubble.right"
        case .wand: "wand.and.stars"
        case .pencil: "pencil.and.scribble"
        case .textCursor: "text.cursor"
        case .keyboard: "keyboard"
        case .brain: "brain.head.profile"
        }
    }
}
