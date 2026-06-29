import Combine
import Foundation

@MainActor
final class AccountStatusService: ObservableObject {
    @Published private(set) var account: AccountStatus?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            guard let token = try await AuthSessionManager.shared.sessionToken() else {
                account = nil
                errorMessage = nil
                return
            }

            var request = URLRequest(url: Self.meURL)
            request.timeoutInterval = 12
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            account = try JSONDecoder().decode(AccountStatus.self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load account status"
        }
    }

    func reset() {
        account = nil
        errorMessage = nil
    }

    private static var meURL: URL {
        let fallbackEndpoint = "https://sayless-production-e6b4.up.railway.app/suggestions"
        let rawEndpoint = nonEmptyString(Bundle.main.object(forInfoDictionaryKey: "SaylessBackendURL") as? String) ?? fallbackEndpoint
        let endpoint = URL(string: rawEndpoint) ?? URL(string: fallbackEndpoint)!

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.path = "/me"
        components?.query = nil

        return components?.url ?? URL(string: "https://sayless-production-e6b4.up.railway.app/me")!
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }
}

struct AccountStatus: Decodable {
    let user: AccountUser
    let plan: String
    let subscription: AccountSubscription?
    let usage: AccountUsage
    let limits: AccountLimits?
}

struct AccountUser: Decodable {
    let id: String
    let stripeCustomerId: String?
}

struct AccountSubscription: Decodable {
    let status: String
    let stripePriceId: String?
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool
}

struct AccountUsage: Decodable {
    let daily: AccountUsagePeriod
    let weekly: AccountUsagePeriod
}

struct AccountUsagePeriod: Decodable {
    let periodStart: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

struct AccountLimits: Decodable {
    let dailySuggestions: Int
    let weeklySuggestions: Int
}
