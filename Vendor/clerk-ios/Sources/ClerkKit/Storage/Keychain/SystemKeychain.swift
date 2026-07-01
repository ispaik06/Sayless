import Foundation

/// A Clerk storage implementation that intentionally avoids macOS Keychain prompts.
///
/// Sayless is distributed without a paid Developer ID certificate, so macOS can show
/// repeated "confidential information" prompts when Clerk reads Keychain items after
/// each locally signed update. This keeps Clerk's internal storage interface intact
/// while persisting the same values under Application Support instead of Keychain.
///
/// Once Sayless has a paid Apple Developer account and stable Developer ID signing,
/// revert this vendored patch and use ClerkKit's upstream Keychain storage again.
/// Upstream Keychain storage is the correct long-term implementation; this patch is
/// only to avoid repeated prompts for ad-hoc / locally signed distribution.
struct SystemKeychain: KeychainStorage {
  enum Accessibility {
    case afterFirstUnlockThisDeviceOnly
  }

  private let service: String

  init(
    service: String,
    accessGroup: String? = nil,
    accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly,
    useDataProtectionKeychain: Bool = false
  ) {
    self.service = service
  }

  func set(_ data: Data, forKey key: String) throws {
    let directory = try storageDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL(forKey: key, in: directory), options: [.atomic])
  }

  func data(forKey key: String) throws -> Data? {
    let url = fileURL(forKey: key, in: try storageDirectory())
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    return try Data(contentsOf: url)
  }

  func deleteItem(forKey key: String) throws {
    let url = fileURL(forKey: key, in: try storageDirectory())
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }

    try FileManager.default.removeItem(at: url)
  }

  func hasItem(forKey key: String) throws -> Bool {
    FileManager.default.fileExists(atPath: fileURL(forKey: key, in: try storageDirectory()).path)
  }

  private func storageDirectory() throws -> URL {
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return baseURL
      .appendingPathComponent("Sayless", isDirectory: true)
      .appendingPathComponent("ClerkStorage", isDirectory: true)
      .appendingPathComponent(safePathComponent(service), isDirectory: true)
  }

  private func fileURL(forKey key: String, in directory: URL) -> URL {
    directory.appendingPathComponent(safePathComponent(key), isDirectory: false)
  }

  private func safePathComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let sanitized = value.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let name = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return name.isEmpty ? "default" : name
  }
}
