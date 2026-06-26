import Foundation

private struct SuggestionRequest: Encodable {
    let chatRoom: String?
    let locale: String
    let draftText: String?
    let intent: SuggestionIntentPayload
    let previousSuggestions: [PreviousSuggestionPayload]
    let messages: [SuggestionMessageGroup]
}

private struct SuggestionIntentPayload: Encodable {
    let kind: String
    let instruction: String?

    init(intent: SuggestionIntent) {
        kind = intent.backendKind
        instruction = intent.instruction
    }
}

private struct PreviousSuggestionPayload: Encodable {
    let label: String
    let text: String
}

private struct SuggestionMessageGroup: Encodable {
    let role: String
    let name: String?
    let texts: [String]
}

private struct SuggestionResponse: Decodable {
    let suggestions: [ReplySuggestion]
}

private struct ReplySuggestion: Decodable {
    let id: String
    let label: String
    let text: String
}

final class BackendSuggestionService {
    private let endpoint = URL(string: "http://127.0.0.1:8787/suggestions")!
    private let locale = "ko-KR"

    func suggestions(
        chatRoom: String,
        messages: [ChatMessage],
        draftText: String,
        intent: SuggestionIntent = .initial,
        previousSuggestions: [Suggestion] = []
    ) async throws -> [Suggestion] {
        let groups = groupedMessages(from: messages)
        guard !groups.isEmpty else {
            return Suggestion.fixed
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SuggestionRequest(
                chatRoom: chatRoom.isEmpty ? nil : chatRoom,
                locale: locale,
                draftText: normalizedDraftText(draftText),
                intent: SuggestionIntentPayload(intent: intent),
                previousSuggestions: previousSuggestions.suffix(18).map {
                    PreviousSuggestionPayload(label: $0.label, text: $0.text)
                },
                messages: groups
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BackendSuggestionError.badStatus
        }

        let decoded = try JSONDecoder().decode(SuggestionResponse.self, from: data)
        let suggestions = decoded.suggestions.prefix(3).enumerated().map { index, item in
            Suggestion(label: normalizedLabel(item.label, index: index, intent: intent), text: item.text)
        }

        return suggestions.count == 3 ? suggestions : Suggestion.fixed
    }

    private func normalizedDraftText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedLabel(_ label: String, index: Int, intent: SuggestionIntent) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if index == 0, intent == .initial {
            return "추천"
        }

        return trimmed.isEmpty ? "옵션 \(index + 1)" : trimmed
    }

    private func groupedMessages(from messages: [ChatMessage]) -> [SuggestionMessageGroup] {
        let recentMessages = messages.suffix(20)
        var groups: [SuggestionMessageGroup] = []

        for message in recentMessages {
            let role = role(for: message.sender)
            let name = name(for: message.sender, role: role)
            let texts = message.text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !texts.isEmpty else {
                continue
            }

            if let last = groups.last,
               last.role == role,
               last.name == name,
               last.texts.count + texts.count <= 8 {
                groups[groups.count - 1] = SuggestionMessageGroup(
                    role: last.role,
                    name: last.name,
                    texts: last.texts + texts
                )
            } else {
                groups.append(
                    SuggestionMessageGroup(
                        role: role,
                        name: name,
                        texts: Array(texts.prefix(8))
                    )
                )
            }
        }

        return Array(groups.suffix(20))
    }

    private func role(for sender: String) -> String {
        sender == "Me" ? "me" : "other"
    }

    private func name(for sender: String, role: String) -> String? {
        guard role == "other",
              sender != "Unknown",
              !sender.isEmpty else {
            return nil
        }

        return sender
    }
}

private enum BackendSuggestionError: Error {
    case badStatus
}
