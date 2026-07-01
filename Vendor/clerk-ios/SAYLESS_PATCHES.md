# Sayless ClerkKit Patch

This vendored copy is based on `clerk-ios` 1.2.6.

Sayless patches `ClerkKit/Storage/Keychain/SystemKeychain.swift` so Clerk session
data is stored under Application Support instead of macOS Keychain. This avoids
repeated "confidential information" Keychain prompts for locally signed builds.

Tradeoff: existing Keychain sessions are not migrated. Users may need to sign in
once after this patch, then the file-backed session should persist across app
restarts and updates.

Important update behavior:
- Users who already signed in on older builds likely start signed out after this
  patch because their old session remains in macOS Keychain and this build no
  longer reads it.
- This is intentional. Reading or deleting the old Keychain item can itself
  trigger the prompt this patch is trying to avoid.
- The old Keychain item is left unused. After the user signs in once on this
  build, Clerk uses the Application Support backed storage instead.

When Sayless has a paid Apple Developer account / Developer ID certificate,
revisit this patch and strongly prefer going back to ClerkKit's upstream
Keychain-backed storage. The upstream approach is the correct long-term storage
model once code signing is stable enough to avoid repeated Keychain prompts.
