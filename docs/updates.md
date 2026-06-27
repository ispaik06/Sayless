# Sayless Updates

Sayless uses Sparkle 2 for in-app updates on macOS.

## Repository Layout

- App source code repo: `Sayless`
- Public update distribution repo: `sayless-updates`
- Local update repo path on this machine: `~/Desktop/sayless-updates`
- GitHub Pages URL:
  `https://ispaik06.github.io/sayless-updates/appcast.xml`
- GitHub Releases asset URL example:
  `https://github.com/ispaik06/sayless-updates/releases/download/v0.1.1/Sayless-0.1.1-2.zip`

The Sayless source repo should only contain source code, scripts, and docs. Do not commit `.zip`, `.dmg`, or `dist/` release artifacts to this repo.

## How Sparkle Updates Work

Sparkle reads `SUFeedURL` from the app's `Info.plist`. That URL points to an `appcast.xml` file. The appcast tells Sparkle what the latest version is and where to download its update archive.

For Sayless:

- GitHub Pages hosts the public `appcast.xml`.
- GitHub Releases hosts the ZIP and DMG files.
- Sparkle downloads the ZIP from the release asset URL.
- Sparkle verifies the ZIP signature with `SUPublicEDKey`.
- If verification passes, Sparkle shows its normal Update / Install and Relaunch flow and replaces the installed app automatically.

Users should not need to download a new DMG and drag Sayless into Applications for every update. That manual DMG flow is only for the first install.

## DMG vs ZIP

Use a DMG for first installation:

- User downloads `Sayless.dmg`.
- User drags `Sayless.app` into Applications.
- This is a familiar macOS first-install UX.

Use a ZIP for Sparkle updates:

- Sparkle expects an update archive that contains `Sayless.app`.
- The ZIP is downloaded and installed by Sparkle.
- `scripts/release-local.sh` creates this update ZIP.

Do not use the first-install DMG as the default Sparkle update archive unless you intentionally change the appcast and test that flow.

## Info.plist Keys

This project uses `Config/Sayless-Info.plist`, referenced from `Sayless.xcodeproj/project.pbxproj`.

Current update keys:

- `SUFeedURL`: `https://ispaik06.github.io/sayless-updates/appcast.xml`
- `SUPublicEDKey`: configured in `Config/Sayless-Info.plist`
- `SUEnableAutomaticChecks`: `true`

Replace these before publishing real updates:

1. Replace `ispaik06` if the GitHub account or Pages URL changes.
2. Make sure `SUPublicEDKey` matches the private key used to sign Sparkle update archives.

The placeholder public key is intentionally allowed for development builds so the app can compile and run. Real update verification will not work until the real Sparkle public key is configured.

## SUPublicEDKey

`SUPublicEDKey` is the public half of Sparkle's EdDSA signing key. Sparkle uses it to verify that a downloaded update ZIP was produced by the app maintainer and was not modified.

The matching private key is used when generating appcast metadata for a release. Keep the private key secret. Only the public key belongs in the app.

## Version Numbers

Sparkle compares versions to decide whether an update is newer.

Sayless uses:

- `CFBundleShortVersionString`: user-facing version, for example `0.1.1`
- `CFBundleVersion`: build number, for example `2`

Always increase `CFBundleVersion` for every published update. If the build number does not increase, Sparkle may decide there is no newer update even if the ZIP changed.

The local release script names update ZIPs like:

```text
Sayless-{CFBundleShortVersionString}-{CFBundleVersion}.zip
```

Example:

```text
Sayless-0.1.1-2.zip
```

## Creating A Local Sparkle ZIP

Build Release first:

```sh
scripts/build-release.sh
```

Avoid putting `-derivedDataPath` inside this repo when building from a synced Desktop/iCloud/File Provider folder. macOS can attach Finder/resource-fork metadata to `.app` bundles there, which makes codesign fail with `resource fork, Finder information, or similar detritus not allowed`.

Then create the Sparkle update ZIP:

```sh
scripts/release-local.sh
```

The ZIP is written to `dist/`, which is ignored by git.

Upload the ZIP to a GitHub Release in the public `sayless-updates` repo. Do not commit the ZIP to either repo.

## Creating A First-Install DMG

After building Release, run:

```sh
scripts/create-dmg.sh
```

The DMG is written to `dist/`. It contains:

- `Sayless.app`
- an `Applications` folder shortcut

This DMG is for first install only. Sparkle updates should normally use the ZIP.

## Updating appcast.xml

The appcast lives in:

```text
~/Desktop/sayless-updates/appcast.xml
```

GitHub Pages publishes that file at:

```text
https://ispaik06.github.io/sayless-updates/appcast.xml
```

GitHub Releases hosts downloadable files like:

```text
https://github.com/ispaik06/sayless-updates/releases/download/v0.1.1/Sayless-0.1.1-2.zip
```

The appcast item must point to the release asset URL and include Sparkle metadata such as version, short version, file length, and signature. The exact signature must be generated with the Sparkle signing tool for the ZIP you upload.

## Why The Updates Repo Is Separate

The public `sayless-updates` repo exists so the app has a stable, public update feed and release asset location. The source repo can stay focused on code review and development history, while the updates repo exposes only what Sparkle needs:

- `appcast.xml` through GitHub Pages
- ZIP/DMG files through GitHub Releases

This also prevents large binary release files from entering the app source history.

## Unsigned Builds And Gatekeeper

Sparkle verifies update archives with its own EdDSA key, but Sparkle does not replace Apple's Developer ID signing or notarization.

If Sayless is distributed unsigned, macOS Gatekeeper may still show warnings when users first install or launch the app. Developer ID signing and notarization should be added later for better installation trust and fewer warnings.

For local development, unsigned DMGs and ZIPs are fine for testing the packaging flow. For public distribution, plan to add Developer ID signing and notarization.

## Failure Behavior

If the appcast URL is missing, private, or incorrect, Sparkle should show/update-fail gracefully instead of crashing the app.

If `SUPublicEDKey` is still `PLACEHOLDER_PUBLIC_ED_KEY`, Sayless keeps the updater from starting real checks and shows that updates are not configured yet. Replace the placeholder key before testing real update verification.
