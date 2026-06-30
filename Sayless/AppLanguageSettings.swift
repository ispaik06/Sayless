import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case korean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        }
    }
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "appLanguage"

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func text(_ english: String, _ korean: String) -> String {
        language == .korean ? korean : english
    }
}
