import Combine
import Foundation

struct ReplyStylePreset: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let instruction: String
}

struct ReplyStyleSlot: Codable, Equatable, Identifiable {
    let id: Int
    var presetID: String
}

struct ReplyStyleSettingsSnapshot: Encodable, Equatable {
    let adjustmentPresets: [ReplyStylePresetPayload]
    let personalInstruction: String?
}

struct ReplyStylePresetPayload: Encodable, Equatable {
    let title: String
    let instruction: String
}

@MainActor
final class ReplyStyleSettings: ObservableObject {
    static let shared = ReplyStyleSettings()
    static let personalInstructionLimit = 70

    static let availablePresets: [ReplyStylePreset] = [
        .init(
            id: "shorter",
            title: "더 짧게",
            systemImage: "textformat.size.smaller",
            instruction: "Make the reply shorter and cleaner without changing the social move."
        ),
        .init(
            id: "softer",
            title: "더 부드럽게",
            systemImage: "leaf",
            instruction: "Make the reply warmer and less sharp without sounding forced."
        ),
        .init(
            id: "wittier",
            title: "더 센스있게",
            systemImage: "sparkles",
            instruction: "Make the reply more clever, playful, or tasteful without forcing a joke."
        ),
        .init(
            id: "direct",
            title: "더 담백하게",
            systemImage: "arrow.forward.circle",
            instruction: "Make the reply direct, clean, and low-drama."
        ),
        .init(
            id: "warm",
            title: "더 다정하게",
            systemImage: "heart",
            instruction: "Make the reply warmer and more affectionate while keeping it natural for KakaoTalk."
        ),
        .init(
            id: "playful",
            title: "더 장난스럽게",
            systemImage: "face.smiling",
            instruction: "Make the reply more playful and casual, but still socially safe."
        ),
        .init(
            id: "polite",
            title: "더 정중하게",
            systemImage: "person.crop.circle.badge.checkmark",
            instruction: "Make the reply polite, composed, and respectful without sounding corporate."
        ),
        .init(
            id: "flirty",
            title: "살짝 플러팅",
            systemImage: "sparkle.magnifyingglass",
            instruction: "Add a subtle flirty edge only if the chat context makes it appropriate."
        ),
        .init(
            id: "strong_flirty",
            title: "플러팅 강하게",
            systemImage: "flame",
            instruction: "Make the reply more boldly flirty and confident when the relationship context supports it; avoid creepiness or pressure."
        ),
        .init(
            id: "calm",
            title: "차분하게",
            systemImage: "moon",
            instruction: "Make the reply calm, measured, and not overly eager."
        ),
        .init(
            id: "rude",
            title: "싸가지없게",
            systemImage: "bolt.horizontal",
            instruction: "Make the reply blunt, prickly, and slightly rude in a chatty way; do not use slurs, threats, or genuinely hateful language."
        ),
        .init(
            id: "annoying",
            title: "킹받게 하기",
            systemImage: "face.dashed",
            instruction: "Make the reply teasing and mildly irritating on purpose, like playful provocation; keep it socially survivable."
        ),
        .init(
            id: "mz",
            title: "MZ 말투",
            systemImage: "bubble.left.and.text.bubble.right.fill",
            instruction: "Use trendy, casual Korean internet-chat phrasing where it fits; avoid overdoing memes."
        ),
        .init(
            id: "make_angry",
            title: "화나게 하기",
            systemImage: "exclamationmark.bubble.fill",
            instruction: "Make the reply more provocative and likely to annoy the other person, but avoid harassment, threats, hate, or escalation beyond the chat context."
        ),
        .init(
            id: "dry_sarcasm",
            title: "비꼬듯이",
            systemImage: "quote.bubble",
            instruction: "Make the reply dry, sarcastic, and cutting without becoming abusive."
        ),
        .init(
            id: "cold",
            title: "차갑게",
            systemImage: "snowflake",
            instruction: "Make the reply cold, distant, and emotionally low-effort."
        ),
        .init(
            id: "overreact",
            title: "오바해서",
            systemImage: "theatermasks",
            instruction: "Make the reply more dramatic and exaggerated for comedic effect."
        ),
        .init(
            id: "push_pull",
            title: "밀당 느낌",
            systemImage: "arrow.left.arrow.right",
            instruction: "Make the reply playful with push-pull tension, confident but not mean."
        )
    ]

    @Published var slots: [ReplyStyleSlot] {
        didSet {
            let normalized = Self.normalizedSlots(slots)
            if normalized != slots {
                slots = normalized
                return
            }
            save()
        }
    }

    @Published var personalInstruction: String {
        didSet {
            let normalized = Self.normalizedPersonalInstruction(personalInstruction)
            if normalized != personalInstruction {
                personalInstruction = normalized
                return
            }
            UserDefaults.standard.set(personalInstruction, forKey: Self.personalInstructionDefaultsKey)
        }
    }

    private static let slotsDefaultsKey = "replyStyleSlots"
    private static let personalInstructionDefaultsKey = "replyStylePersonalInstruction"

    private init() {
        slots = Self.loadSlots()
        personalInstruction = Self.normalizedPersonalInstruction(
            UserDefaults.standard.string(forKey: Self.personalInstructionDefaultsKey) ?? ""
        )
    }

    func preset(for slot: ReplyStyleSlot) -> ReplyStylePreset {
        Self.availablePresets.first { $0.id == slot.presetID } ?? Self.availablePresets[slot.id]
    }

    func preset(for option: SuggestionAdjustmentOption) -> ReplyStylePreset? {
        guard let slotIndex = option.styleSlotIndex,
              slots.indices.contains(slotIndex) else {
            return nil
        }

        return preset(for: slots[slotIndex])
    }

    func setPresetID(_ presetID: String, for slotID: Int) {
        guard slots.indices.contains(slotID),
              Self.availablePresets.contains(where: { $0.id == presetID }) else {
            return
        }

        slots[slotID].presetID = presetID
    }

    func snapshot() -> ReplyStyleSettingsSnapshot {
        ReplyStyleSettingsSnapshot(
            adjustmentPresets: slots.map { slot in
                let preset = preset(for: slot)
                return ReplyStylePresetPayload(title: preset.title, instruction: preset.instruction)
            },
            personalInstruction: Self.optionalPersonalInstruction(personalInstruction)
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(slots) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.slotsDefaultsKey)
    }

    private static func loadSlots() -> [ReplyStyleSlot] {
        guard let data = UserDefaults.standard.data(forKey: slotsDefaultsKey),
              let decoded = try? JSONDecoder().decode([ReplyStyleSlot].self, from: data) else {
            return defaultSlots
        }

        return normalizedSlots(decoded)
    }

    private static var defaultSlots: [ReplyStyleSlot] {
        [
            .init(id: 0, presetID: "shorter"),
            .init(id: 1, presetID: "softer"),
            .init(id: 2, presetID: "wittier")
        ]
    }

    private static func normalizedSlots(_ slots: [ReplyStyleSlot]) -> [ReplyStyleSlot] {
        let validIDs = Set(availablePresets.map(\.id))
        let fallback = defaultSlots

        return (0..<3).map { index in
            let presetID = slots.first { $0.id == index }?.presetID ?? fallback[index].presetID
            return ReplyStyleSlot(
                id: index,
                presetID: validIDs.contains(presetID) ? presetID : fallback[index].presetID
            )
        }
    }

    private static func normalizedPersonalInstruction(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(normalized.prefix(personalInstructionLimit))
    }

    private static func optionalPersonalInstruction(_ value: String) -> String? {
        let normalized = normalizedPersonalInstruction(value)
        return normalized.isEmpty ? nil : normalized
    }
}
