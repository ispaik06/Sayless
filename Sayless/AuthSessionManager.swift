import ClerkKit
import Combine
import Foundation
import Security

@MainActor
final class AuthSessionManager: ObservableObject {
    static let shared = AuthSessionManager()

    @Published private(set) var clerk: Clerk
    @Published private(set) var configurationError: String?
    @Published private(set) var isLoadingRemoteConfiguration = false

    private init() {
        Self.prepareClerkKeychainStorageIfNeeded()

        if let publishableKey = Self.publishableKey {
            clerk = Clerk.configure(publishableKey: publishableKey, options: Self.clerkOptions)
        } else {
            configurationError = "Loading Clerk configuration..."
            clerk = Clerk.configure(publishableKey: Self.placeholderPublishableKey, options: Self.clerkOptions)
            Task {
                await loadRemoteConfiguration()
            }
        }
    }

    var isSignedIn: Bool {
        clerk.user != nil
    }

    var userDisplayName: String {
        guard let user = clerk.user else {
            return "Not signed in"
        }

        if let primaryEmail = user.primaryEmailAddress?.emailAddress,
           !primaryEmail.isEmpty {
            return primaryEmail
        }

        let fullName = [user.firstName, user.lastName]
            .compactMap { $0 }
            .joined(separator: " ")

        return fullName.isEmpty ? user.id : fullName
    }

    func sessionToken() async throws -> String? {
        try await clerk.auth.getToken()
    }

    func signOut() {
        Task {
            try? await clerk.auth.signOut()
        }
    }

    func loadRemoteConfiguration() async {
        guard !isLoadingRemoteConfiguration else {
            return
        }

        isLoadingRemoteConfiguration = true
        defer {
            isLoadingRemoteConfiguration = false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.authConfigURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let config = try JSONDecoder().decode(AuthConfigResponse.self, from: data)
            let publishableKey = try Self.validatedPublishableKey(config.clerkPublishableKey)
            clerk = try await Clerk.reconfigure(publishableKey: publishableKey, options: Self.clerkOptions)
            configurationError = nil
        } catch {
            configurationError = "Unable to load Clerk configuration"
        }
    }

    private static var clerkOptions: Clerk.Options {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ispaik.Sayless"
        let keychainService = "\(bundleIdentifier).clerk.v3"

        return Clerk.Options(
            telemetryEnabled: false,
            keychainConfig: .init(service: keychainService)
        )
    }

    private static func prepareClerkKeychainStorageIfNeeded() {
        let storageGenerationKey = "clerkKeychainStorageGeneration"
        let currentGeneration = 3
        guard UserDefaults.standard.integer(forKey: storageGenerationKey) < currentGeneration else {
            return
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ispaik.Sayless"
        let legacyServices = [
            bundleIdentifier,
            "\(bundleIdentifier).clerk.v2",
            "\(bundleIdentifier).clerk.debug.\(ProcessInfo.processInfo.processIdentifier)"
        ]

        for service in legacyServices {
            deleteGenericPasswordItems(service: service)
        }

        UserDefaults.standard.set(currentGeneration, forKey: storageGenerationKey)
    }

    private static func deleteGenericPasswordItems(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }

    private static var publishableKey: String? {
        nonEmptyString(Bundle.main.object(forInfoDictionaryKey: "ClerkPublishableKey") as? String)
            ?? nonEmptyString(Bundle.main.object(forInfoDictionaryKey: "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY") as? String)
            ?? nonEmptyString(ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"])
            ?? nonEmptyString(ProcessInfo.processInfo.environment["NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"])
    }

    private static var authConfigURL: URL {
        let fallbackEndpoint = "https://sayless-production-e6b4.up.railway.app/suggestions"
        let rawEndpoint = nonEmptyString(Bundle.main.object(forInfoDictionaryKey: "SaylessBackendURL") as? String) ?? fallbackEndpoint
        let endpoint = URL(string: rawEndpoint) ?? URL(string: fallbackEndpoint)!

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.path = "/auth/config"
        components?.query = nil

        return components?.url ?? URL(string: "https://sayless-production-e6b4.up.railway.app/auth/config")!
    }

    private static let placeholderPublishableKey = "pk_test_c2F5bGVzcy1jb25maWd1cmF0aW9uLXBlbmRpbmc"

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }

    private static func validatedPublishableKey(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("pk_") else {
            throw URLError(.badServerResponse)
        }

        return trimmed
    }
}

private struct AuthConfigResponse: Decodable {
    let clerkPublishableKey: String
}
