import Foundation

private struct SuggestionRequest: Encodable {
    let chatRoom: ChatRoomPayload?
    let locale: String
    let draftText: String?
    let intent: SuggestionIntentPayload
    let previousSuggestions: [PreviousSuggestionPayload]
    let activeSuggestions: [PreviousSuggestionPayload]?
    let messages: [SuggestionMessageGroup]
}

private struct ChatRoomPayload: Encodable {
    let title: String?
    let participantCount: Int?
}

private struct SuggestionIntentPayload: Encodable {
    let kind: String
    let refreshIndex: Int?
    let instruction: String?

    init(intent: SuggestionIntent) {
        kind = intent.backendKind
        refreshIndex = intent.refreshIndex
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

private struct BackendErrorResponse: Decodable {
    let message: String?
}

final class BackendSuggestionService {
    private let endpoint = URL(string: "http://127.0.0.1:8787/suggestions")!
    private let locale = "ko-KR"
    private let requestTimeout: TimeInterval = 18

    func suggestions(
        chatRoom: String,
        participantCount: Int?,
        messages: [ChatMessage],
        draftText: String?,
        intent: SuggestionIntent = .initial,
        previousSuggestions: [Suggestion] = [],
        activeSuggestions: [Suggestion]? = nil
    ) async throws -> [Suggestion] {
        let groups = groupedMessages(from: messages)
        guard !groups.isEmpty else {
            throw BackendSuggestionError.emptyMessages
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SuggestionRequest(
                chatRoom: chatRoomPayload(title: chatRoom, participantCount: participantCount),
                locale: locale,
                draftText: normalizedDraftText(draftText),
                intent: SuggestionIntentPayload(intent: intent),
                previousSuggestions: previousSuggestions.suffix(18).map {
                    PreviousSuggestionPayload(label: $0.label, text: $0.text)
                },
                activeSuggestions: normalizedActiveSuggestions(activeSuggestions),
                messages: groups
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendSuggestionError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let backendError = try? JSONDecoder().decode(BackendErrorResponse.self, from: data)
            throw BackendSuggestionError.badStatus(backendError?.message)
        }

        let decoded = try JSONDecoder().decode(SuggestionResponse.self, from: data)
        let suggestions = decoded.suggestions.prefix(3).enumerated().map { index, item in
            Suggestion(label: normalizedLabel(item.label, index: index), text: item.text)
        }

        guard suggestions.count == 3 else {
            throw BackendSuggestionError.invalidResponse
        }

        return suggestions
    }

    private func normalizedDraftText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedParticipantCount(_ count: Int?) -> Int? {
        guard let count,
              count > 1 else {
            return nil
        }

        return count
    }

    private func chatRoomPayload(title: String, participantCount: Int?) -> ChatRoomPayload? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedParticipantCount = normalizedParticipantCount(participantCount)

        guard !normalizedTitle.isEmpty || normalizedParticipantCount != nil else {
            return nil
        }

        return ChatRoomPayload(
            title: normalizedTitle.isEmpty ? nil : normalizedTitle,
            participantCount: normalizedParticipantCount
        )
    }

    private func normalizedActiveSuggestions(_ suggestions: [Suggestion]?) -> [PreviousSuggestionPayload]? {
        guard let suggestions,
              suggestions.count == 3 else {
            return nil
        }

        return suggestions.map {
            PreviousSuggestionPayload(label: $0.label, text: $0.text)
        }
    }

    private func normalizedLabel(_ label: String, index: Int) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum BackendSuggestionError: LocalizedError {
    case emptyMessages
    case transport(Error)
    case badStatus(String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyMessages:
            return "표시된 대화가 부족합니다"
        case .transport(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return "백엔드 응답 시간이 초과되었습니다. 다시 시도해 주세요"
                case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                    return "백엔드에 연결할 수 없습니다"
                default:
                    break
                }
            }

            return "백엔드 요청 중 오류가 발생했습니다"
        case .badStatus(let message):
            return message ?? "백엔드 응답을 받을 수 없습니다"
        case .invalidResponse:
            return "백엔드 응답 형식이 올바르지 않습니다"
        }
    }
}
